+++
categories = [ "tech" ]
tags = [ "network", "xdp", "ebpf", "cilium", "golang" ]
date = 2021-10-07
title = "Goのcilium/ebpfでXdpcapを使う"
description = "GoのeBPFライブラリcilium/ebpfでxdpcapを使います"
+++

こんにちは．学生生活も後少しとなってしまいました．悲しいです．
今回はxdpcapというツールについてです．xdpcapの使用に関する資料が日本語では非常に少なかったので使い方を紹介します．

<!--more-->

## cloudflare/xdpcap

{{<github repo="cloudflare/xdpcap">}}

[cloudflare/xdpcap](https://github.com/cloudflare/xdpcap)はeXpress Data Path(XDP)を利用したtcpdumpのように使えるツールです．
xdpcapはtcpdumpで使用するのと同様のフィルタリングルールを使用してパケットをキャプチャしたり，pcapファイルにダンプすることができます．

xdpで編集したパケットはtcpdumpでは見えなくなるのでちゃんとパケットの組み立てができているかわかりません．
このツールの嬉しさはxdpで編集後のパケットをtcpdumpと同じようにキャプチャできることです．


### tcpdumpとの違い
tcpdumpは内部でパケットをフィルタリングする際にcBPFを利用しますが，xdpcapはxdpを使用します．
xdpcapでキャプチャしたパケットはxdpプログラムによって変更が加えられた後のパケットです．
また，xdp action codeも同時にキャプチャしてくれます．
xdp action codeには以下のようなものがあります．
- XDP_PASS
- XDP_DROP
- XDP_ABORTED
- XDP_TX
- XDP_REDIRECT

### 手法
xdpcapではフィルタリングするためにxdpcapが使えるebpfマップをフックしてあげる必要があります．
このフックはeBPFの`tail call`を使用して実現されています．
`tail call`はbpfプログラムから別のbpfプログラムを呼び出すための機能です．
詳しくは[cilium document: tail calls](https://docs.cilium.io/en/stable/bpf/#tail-calls)を参照してください．
`tail call`を行うためには`BPF_MAP_TYPE_PROG_ARRAY`というタイプのbpf mapが必要です．さらに`bpf_tail_call()`というヘルパー関数が用意されている必要があります．
xdpcapはこの`tail call`を利用してユーザーが定義したxdpプログラムがリターンする際のコンテキストを引き継いでxdpcapのbpfプログラムによりキャプチャされます．
詳しくは[xdpcap: XDP Packet Capture](https://blog.cloudflare.com/xdpcap/)を参照してください．

### 使い方
今回作成したプログラムは[terassyi/xdpcap-with-cilium](https://github.com/terassyi/xdpcap-with-cilium)にあります．

{{<github repo="terassyi/xdpcap-with-cilium">}}

#### 環境
本プログラムの動作環境は以下です．
- `Linux ip-172-31-20-186 5.11.0-1019-aws #20~20.04.1-Ubuntu SMP Tue Sep 21 10:40:39 UTC 2021 x86_64 x86_64 x86_64 GNU/Linux`
- `go 1.16`
- `clang version 10.0.0-4ubuntu1`

#### 前準備
まずxdpcapをインストールします．
`xdpcap`を使用するためには`bpffs`がマウントされている必要があります．
マウントは以下のコマンドで行えます．
```shell
$ sudo mount -t bpf none /sys/fs/bpf
```

### 実行
1. `make`コマンドでビルドします．
	```shell
	$ make
	```
2. ビルドされた実行ファイルを以下のように実行します．
	```shell
	$ sudo ./xdpcap-with-cilium -iface <interface>
	```
3. 別ターミナルで以下のコマンドを実行することでパケットのキャプチャとファイルへの保存を行うことができます．
	```shell
	$ sudo xdpcap /sys/fs/bpf/xdpcap <pcap file> "filter rules"
	```
	```shell
	sudo xdpcap /sys/fs/bpf/xdpcap - "filter rules" | sudo tcpdump -r -
	```

### 実装

#### XDP Program

`bpf`配下にxdp用のプログラムがあります．
ディレクトリの構成は以下です．
```
bpf
├── header
│   ├── bpf.h
│   └── bpf_helpers.h
├── hook.h
└── prog.c
```
`bpf/header`配下にある`bpf.h`, `bpf_helpers.h`は[dropbox/goebpf](https://github.com/dropbox/goebpf)から借用しています．必要なものが定義されているならどれでも構いません．
`bpf/hook.h`にxdpcapのための関数が定義されています．
内容はフック用の`PROG_ARRAY`のマップの定義と`tail_call`をラップした`xdpcap_exit()`関数のみなので`prog.c`にコピペしてもかまいません．
`prog.c`でも特に何もしていません．ただ`XDP_PASS`でパケットをパスしますが`xdpcap_exit()`を呼び出すことでxdpcapのbpfプログラムをtail callします．
```c
#include "hook.h"
#include "bpf_helpers.h"

BPF_MAP_DEF(xdpcap_hook) = {
	.map_type = BPF_MAP_TYPE_PROG_ARRAY,
	.key_size = sizeof(int),
	.value_size = sizeof(int),
	.max_entries = 5,
};
BPF_MAP_ADD(xdpcap_hook);


SEC("xdp")
int prog(struct xdp_md *ctx) {
	return xdpcap_exit(ctx, &xdpcap_hook, XDP_PASS);
}
```

#### Go program
今回はxdpのフロントとして[cilium/ebpf](https://github.com/cilium/ebpf)を使用しています．

ciliumには`bpf2go`というパッケージがあって`bpf2go`経由でbpfプログラムをビルドすることでbpfプログラムをGo側でロードするためのインターフェースとなるGoのコードを自動生成してくれます．
自動生成されたコードのなかにコンパイルしたbpfのバイトコードをバイトスライスとして保存しているためGoのコードをビルドするとあとはシングルバイナリで動作します．
main.goに以下の行を追加することで`go generate`によりコードを自動生成できます．
```
//go:generate go run github.com/cilium/ebpf/cmd/bpf2go -cc clang XdpcapProg ./bpf/prog.c -- -I./bpf/header
```

続いてbpfプログラムのロードとアタッチ，bpfマップのピンです．
`Collect`という型を定義してbpfプログラムとマップをGo側で保持するための構造体を作ります．
```go
type Collect struct {
	XdpProg *ebpf.Program `ebpf:"prog"`
	XdpcapHook *ebpf.Map `ebpf:"xdpcap_hook"`
}
```
そして`bpf2go`により自動生成される関数を使用してbpfプログラムをロードします．
```go
spec, err := LoadXdpcapProg()
if err != nil {
	panic(err)
}
if err := spec.LoadAndAssign(collect, nil); err != nil {
	panic(err)
}
if err := netlink.LinkSetXdpFd(link, collect.XdpProg.FD()); err != nil {
	panic(err)
}
```
その後，bpfマップのbpffsへのピンを行います．
```go
tmpDir := "/sys/fs/bpf/xdpcap"
if err := collect.XdpcapHook.Pin(tmpDir); err != nil {
	panic(err)
}
```

実装は以上となります．ほぼ何もしないので実装は簡単です．

## まとめ
今回は`xdpcap`というxdpを利用したパケットキャプチャツールの使い方を紹介しました．
xdpを使うときは編集したパケットをのぞくのが難しいので使えると便利です．
xdp関連の話題は日本語の資料がないので参考になれば幸いです．


## 参考資料　

### cloudflare/xdpcap
- [xdpcapを使ってみる](https://blog.masu-mi.me/post/2021/01/29/try-to-use-xdpcap/)
- [xdpcap: XDP Packet Capture](https://blog.cloudflare.com/xdpcap/)

### cilium/ebpf
- [cilium document: tail calls](https://docs.cilium.io/en/stable/bpf/#tail-calls)
