+++
categories = [ "activity" ]
tags = [ "intern", "klab", "network", "tcp", "golang" ]
date = 2021-03-13
title = "KLab Expert Camp TCP/IPプロトコルスタック自作開発キャンプに参加してきました．"
description = "3/3-9で開催されたKLab Expert Campに参加してTCP/IPプロトコルスタックを自作しました．"
+++

こんにちは．趣味の将棋がなかなか強くならなくて困ってます．勉強せずにすぐ対局してしまうのがダメなのはわかってますがつい対局してしまいます．
今回はKLab Expert Campに参加してTCP/IPプロトコルスタック自作に挑戦しました．

<!--more-->

## 経緯
最初にこのイベントについて知ったのは昨年の[第一回TCP/IPプロトコルスタック自作キャンプ](https://www.klab.com/jp/blog/pr/2019/51714636.html)に参加されていた参加者の方のツイートとブログでした．ちょうど僕もTCP/IPの自作を行う機運が高まっていたので次回があれば絶対参加するぞと思っていました．

{{<x user="terassyi_" id="1227190490690310145">}}

## KLab Expert Camp(TCP/IPプロトコルスタック自作開発)
[microps](https://github.com/pandax381/microps)や[lectcp](https://github.com/pandax381/lectcp)を開発されている[pandax381](https://twitter.com/pandax381)さんに直接解説やアドバイスをいただきながらTCP/IPを実装していくというものです．

基本コースと発展コースが用意されており基本コースは講義形式でmicropsを参考に実装を行い，発展コースは自身の持ち込んだテーマでTCP/IPに関する開発を行います．
僕はGo言語で自作TCP/IPをすでに開発中でTCPも少し動いていたので自作のプロトコルスタックにwindow制御などの機能追加をしたいと思っていました．


僕の自作TCP/IPのリポジトリはこちら

{{<github repo="terassyi/gotcp">}}

## やったこと
やったことの概要は成果発表の資料にまとめてます．

<iframe src="https://docs.google.com/presentation/d/e/2PACX-1vRZYaCiABE150hJnZpE3zaaKzzlg1qSQ77zFKg-ht0zcKOCCJcFlR9PuaBRh4g9dGrvyTbwyklpeWeb/embed?start=false&loop=false&delayms=3000" frameborder="0" width="480" height="299" allowfullscreen="true" mozallowfullscreen="true" webkitallowfullscreen="true"></iframe>

成果発表スライドをチラッとみていただければ分かりますが期間中進捗はほぼほぼなしで永遠にデバッグしてました．とはいえ自分一人では気づかなかったバグや仕様の落とし穴などを指摘していただけたので貴重な経験でした．結果としてデバッグも進んだのでよかったです．

スライドで上げているバグとそれに対してやったことについて軽く紹介します．

### RFC793に書かれている仕様が現実の実装と異なる場合がある
これは`PSHフラグ`問題です．TCPは到着したセグメントを格納しておくバッファを持っています．
そしてRFC793の仕様には以下のような記述があります．
> There is a coupling between the push function and the use of buffers
  of data that cross the TCP/user interface.  Each time a PUSH flag is
    associated with data placed into the receiving user’s buffer, the
	  buffer is returned to the user for processing even if the buffer is
	    not filled.  If data arrives that fills the user’s buffer before a
		  PUSH is seen, the data is passed to the user in buffer size units.

つまり，TCPはPSHフラグが検出される，もしくはバッファがいっぱいになったらアプリケーションにデータを投げるということになっています．
ということで僕が当初書いていたコードがこちら．

セグメントの処理部．
```go
if packet.Packet.Header.OffsetControlFlag.ControlFlag().Psh() {
	//c.readyQueue <- packet.Packet.Data
	c.rcvBuffer = append(c.rcvBuffer, packet.Packet.Data...)
	c.readyQueue <- c.rcvBuffer

} else {
	c.rcvBuffer = append(c.rcvBuffer, packet.Packet.Data...)
	if len(c.rcvBuffer) >= cap(c.rcvBuffer) {
		c.readyQueue <- c.rcvBuffer
}
// ...
```

Read処理部
```go
func (c *Conn) read(b []byte) (int, error) {
	buf, ok := <-c.readyQueue
	if !ok {
		return 0, fmt.Errorf("failed to read")
	// ...
```

しかし現在のSocket APIは能動的にデータを上位層に渡す手段は持っていません．実際の実装ではシステムコールを使用してreadするのでアプリケーション側が任意のタイミングでデータを読み出します．つまり，PSHフラグは現在意味をなさず，TCPは到着したデータを単にバッファに詰め込んでアプリケーションからの読み出しを待ちます．

というわけで実装を変更しました．
```go
// Do not check PSH flag.
l := len(packet.Packet.Data)
if len(c.rcvBuffer.buf)+l >= cap(c.rcvBuffer.buf) {
	c.rcvBuffer.init()
	c.tcb.rcv.WND = window
	c.rcvBuffer.buf = append(c.rcvBuffer.buf, packet.Packet.Data...)
	c.tcb.rcv.NXT = c.tcb.rcv.NXT + uint32(l)
	c.tcb.rcv.WND = c.tcb.rcv.WND - uint32(l)
	// ...
}
```
セグメント処理部では単に到着したデータをバッファに詰め込みます．
```go
func (c *Conn) read(b []byte) (int, error) {
	if _, ok := <-c.rcvBuffer.readable; !ok {
		return 0, fmt.Errorf("failed to recv")
	}
	l := copy(b, c.rcvBuffer.buf)
	c.rcvBuffer.init()
	c.tcb.rcv.WND = window
	return l, nil
}
```
Read処理部ではバッファがreadableならバッファをコピーします．

RFC793は昔に策定された仕様なので実際の実装とは異なる場合があるようです．歴史を感じます．

### パケットがどこかへ消えてしまう(未解決問題)

ある程度大きなデータを送受信しようとすると途中でパケットが欠損してしまい応答ができなくなるという問題がありました．
EthernetからTCPまで結構複雑にgoroutineとchannelを使用してデータを送受信しています．
非同期処理の中でデータが落ちてるのかなと思いデバッグしてましたが期間中に修正することはできず時間切れでした．

当時の僕
{{<x user="terassyi_" id="1368878451071930376">}}

#### 解決

{{<x user="terassyi_" id="1369499414121750533">}}

期間中は間に合いませんでしたが原因はgoroutineとchannelのスイッチングの問題でうまく処理ができていないことのようでした．原因は詳しく調査できていませんが以下のようにchannel受信処理の前にsleepを挟むとうまく動作しました．
```go
for {
	time.Sleep(time.Millisecond * 100)
	buf, ok := <-rcvQueue
	// ...
}
```

## まとめ
期間中はpandax381さんをはじめKLabの方々に様々なサポートをしていただきました．ありがとうございました．いただいたお菓子も非常に美味しかったです．結果としてほぼほぼ全期間デバッグで終わってしまいましたが一人では気づけない箇所に気づくことができたので非常に有意義でした．

詳しいTCP/IPの実装などはまた別に記事にできればなと思います．
貴重な機会をいただきましてありがとうございました．

<!-- https://x.com/terassyi_/status/1366268368106385408 -->
