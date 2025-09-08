+++
categories = [ "activity" ]
tags = [ "intern", "pepabo", "ebpf", "network" ]
date = 2020-09-12
title = "GMOペパボの研究開発コースインターンシップに参加しました"
description = "9/8-10で開催されたGMOペパボ研究開発インターンシップに参加しました．３日間でeBPFを使用したツール作成を行いました．"
+++

## 参加の経緯
確か最初にインターンの開催を知ったのはtwitterだったと記憶しています．エンジニアインターンはWeb系の募集がほとんどで低レイヤを扱うインターンを探していたので即応募しました．

## 内容
僕が参加したのは研究開発/SREコースでeBPFを使用したトレーシングツールの作成を行いました．`eBPF`とは`extended Berkeley Packet Filter`の略でユーザー空間からプログラムを挿入してカーネル空間のデータを取得することができる技術です．
今回のインターンでは[Uchio Kondo](https://twitter.com/udzura)さんと[P山](https://twitter.com/pyama86)さんにメンターとしてついていただきeBPFのチュートリアルから初めて最終的に参加者それぞれが一つのツールにまとめて成果として最終日に発表しました．お二方には期間中とても手厚くサポートしていただきました．ありがとうございました．

<!--more-->

### 1日目
１日目の午前中は自己紹介などを行い，午後からコースに別れてプログラムがスタートしました．
eBPFをまともに触ったことがなかったのでまずは環境のセットアップから初めて，サポートしていただきながら[bcc Python Developer Tutorial](https://github.com/iovisor/bcc/blob/master/docs/tutorial_bcc_python_developer.md)を進めました．

### 2日目
この日は終日コースワークを行いました．自分が作成するツールのテーマを決めて，午前は前日やり残したチュートリアルを進めました．午後からは決定したテーマのツールの実装に入りました．僕は既存のツール[bcc/tools/tcpaccept](https://github.com/iovisor/bcc/blob/v0.13.0/tools/tcpaccept.py)をコンテナのトレース向けに改良しました．

### 3日目
午前と午後の半分は引き続き実装を行いました．実装はeBPFでは(できるかもしれないけど)難しいところもあり，最初に考えていた機能を全て実装することはできませんでしたが，ギリギリ使えそうなものとしてまとめることができました．
その後は成果発表を行い，懇親会が開催されました．成果発表はみなさん面白い発表をされており非常に楽しかったです．懇親会も社員のみなさんと他のインターン生と交流できて楽しかったです．
写真は僕がツールのデモを行っている画面です．
![pepabo-presentation](/img/pepabo-presentation.png)

## 成果
僕が元にしたツールである`tcpaccept`はTCPのコネクションが確立した時にその宛先アドレスやポート，PIDなどをトレースしてくれるものです．今回僕はこれに対してコネクションがコンテナプロセスかどうかを調べてコンテナIDを合わせて取得できるようにしました．コンテナIDによるフィルタリングを行うことができるように実装しました．本来はコンテナ内のPIDまで取得できるようにしたかったのですが，少し難しいとのことでしたので今回は諦めました．
コードはこちらです．[container-tcpaccept](https://github.com/terassyi/container-tcpaccept)

## まとめ
今回は`eBPF`という新しい技術をプロの方から学ぶことができて非常に貴重な経験をすることができました．
`eBPF`は以前から興味があったのですが如何せん資料が少ないため手を出すのを躊躇っていました．これを機にもっと自分でも掘り下げてみようと思います．また，Linux Kernelの知識がどうしても必要になるので漠然と読むよりこのような形での方がモチベーションが上がるので`eBPF`を通してLinux Kernelを学べたら良いなと思います．

## お礼
今回インターンシップに受け入れていただいたGMOペパボのみなさんに感謝申し上げます．また，期間中大変お世話になった[Uchio Kondo](https://twitter.com/udzura)さんと[P山](https://twitter.com/pyama86)さんに重ねてお礼申し上げます．ありがとうございました．

## おまけ
圧(?)をかけられブログを後回しにしがちな僕も早めにポストできました．

{{<x user="terassyi_" id="1304051654518431744">}}

今回インターンでいただいたお賃金は[詳解Linuxカーネル](https://www.amazon.co.jp/%E8%A9%B3%E8%A7%A3-Linux%E3%82%AB%E3%83%BC%E3%83%8D%E3%83%AB-%E7%AC%AC3%E7%89%88-Daniel-Bovet/dp/487311313X)と[Webで使えるmrubyシステムプログラミング入門](https://www.amazon.co.jp/dp/4863543298/)を買う資金にします．

## 参考
- [eBPF - IO Visor Project](https://www.iovisor.org/technology/ebpf)


<disqus/>

<script>
import { Tweet } from 'vue-tweet-embed/dist'

export default {
    components: {Tweet}
}
</script>
