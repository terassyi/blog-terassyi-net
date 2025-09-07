+++
categories = [ "tech" ]
tags = [ "network", "xdp", "ebpf", "cilium", "golang" ]
date = 2021-10-18
title = "XDP入門"
description = "XDPに入門します"
+++

こんにちは．閃光のハサウェイが配信開始されたので早速視聴しました．メッサーがいいですね．

前回もXDP関連の話題でしたが，今回はXDPに入門します．
XDPを学習する際のロードマップやつまりどころの解消になればと思います．

### 2023-12-30 加筆

本記事を公開して約 2 年が経過しました.
この加筆で古くなってしまった情報を修正しています.
差分は このブログの Github の [PR](https://github.com/terassyi/blog/pull/57/files) を見てください.

この 2 年間で eBPF 及び XDP への注目はさらに高まったように感じます.
取得できる情報も充実してきました.
特に O'reilly より発売された [入門 eBPF](https://www.oreilly.co.jp/books/9784814400560/)(原書: [Learning eBPF](https://www.oreilly.com/library/view/learning-ebpf/9781098135119/)) は非常に充実した内容になっています.
日本語でこれらの情報に触れられるようになったことは大変ありがたいです.

2023 年は個人的にも XDP に関して新たに発展的なコンテンツを作成しました.

そちらも触っていただければと思います.

{{<github repo="terassyi/seccamp-xdp">}}

<!--more-->

## XDP
XDPとはeXpress Data Pathの略でLinuxカーネル内で動作するeBPFベースの高性能なパケット処理技術です．
制限のあるC言語で記述したプログラムをBPFバイトコードにコンパイルし，NICにアタッチすることでカーネルのプロトコルスタックより手前でパケット処理を行うことができます．
XDPには以下のようなメリットがあります．
- カーネルを修正することなく柔軟にパケット処理機能を実装することができる
- 特別なハードウェアを準備することなく利用することができる
- 高速にパケットを処理することができる
- 既存のTCP/IPスタックを置き換えることなく協調して動作させることができる

## ユースケース
XDPのユースケースとして以下のようなものがあります．
- DDos攻撃の軽減
	- [Cloudflare Gatebot](https://blog.cloudflare.com/l4drop-xdp-ebpf-based-ddos-mitigations/)
- L4ロードバランサ
	- [Facebook Katran](https://engineering.fb.com/2018/05/22/open-source/open-sourcing-katran-a-scalable-network-load-balancer/)
	- [LINE](https://speakerdeck.com/line_devday2019/software-engineering-that-supports-line-original-lbaas)
- NAT
	- [XFLAG](https://speakerdeck.com/mabuchin/zhuan-binagaramonetutowakuchu-li-wo-sohutoueadezi-zuo-siteikuhua)
- Kubernetes Networking(LB, Conntrack, Network policy)
	- [Cilium](https://cilium.io/)
- Router

## アーキテクチャ(仕組み)
XDPプログラムはC言語として記述し，BPFバイトコードにコンパイルします．
また，BPF Verifierによりメモリアクセスやループなどを静的に検査してNICにロードします．

プログラムがアタッチされるとパケットの着信の度にNICのデバイスドライバ内でフックされてプログラムが実行されます．
そのため`sk_buff`が生成されるより前の段階でパケットを編集することができます．
![xdp-packet-processing](/img/xdp-packet-processing.png)

### XDP Actions
XDPプログラムはそのXDP Actions(終了コード)によってパケットを制御します．
サポートされているXDP Actionsは以下です．
- XDP_PASS
	- パケットをOSのプロトコルスタックに流す.
- XDP_DROP
	- パケットをドロップする.
- XDP_TX
	- パケットを受信したNICから送出する．
- XDP_ABORTED
	- BPFのエラーを返す際に使用する．パケットはドロップする．
- XDP_REDIRECT
	- 受信したパケットを`DEVMAP`に登録されたNICから送出する．

### BPF Map
BPFプログラムはカーネル内にロードされます．BPFプログラム(カーネル空間)とユーザー空間でデータをやり取りする手段としてBPFマップがあります．

![Linux-kernel-eBPF-architecture](/img/Linux-kernel-eBPF-architecture.png)

BPFマップは任意の型のKey-Value連想配列です．bpfシステムコールによって作成，値の追加，削除，参照などが行われます．

### BPF Map Type
BPFマップはその用途に対して25種類のタイプが存在します．
ユーザーは自身の用途に合わせたマップを使用することができます．
各タイプは以下のようになっています．
- BPF_MAP_TYPE_UNSPEC
- **BPF_MAP_TYPE_HASH**
	- 単純なハッシュ．
- **BPF_MAP_TYPE_ARRAY**
	- 単純な配列．要素の削除はできない
- **BPF_MAP_TYPE_PROG_ARRAY**
	- `tail_call`(詳しくは前エントリ([Goのcilium/ebpfでXdpcapを使う](https://terassyi.net/posts/2021/10/07/use-xdpcap.html#%E6%89%8B%E6%B3%95)))のジャンプテーブルとして使用される配列
- **BPF_MAP_TYPE_PERF_EVENT_ARRAY**
	- `bpf_perf_event_output()`の結果が保持される．ユーザースペースのプログラムはそれをpoll()してあげる．
- **BPF_MAP_TYPE_PERCPU_HASH**
	- CPUごとに割り当てられるハッシュ．
- **BPF_MAP_TYPE_PERCPU_ARRAY**
	- CPUごとに割り当てられた配列．
- BPF_MAP_TYPE_STACK_TRACE
- BPF_MAP_TYPE_CGROUP_ARRAY
- **BPF_MAP_TYPE_LRU_HASH**
	- LRUハッシュ
- **BPF_MAP_TYPE_LRU_PERCPU_HASH**
	- CPUごとのLRUハッシュ
- ***BPF_MAP_TYPE_LPM_TRIE***
	- longest-prefixマッチをサポートしたマップ．ルートテーブルなどを作る際に使用する．
- BPF_MAP_TYPE_ARRAY_OF_MAPS
- BPF_MAP_TYPE_HASH_OF_MAPS
- ***BPF_MAP_TYPE_DEVMAP***
	- `bpf_redirect()`に使用する．NIC間のリダイレクト用．
- BPF_MAP_TYPE_SOCKMAP
- BPF_MAP_TYPE_CPUMAP
- BPF_MAP_TYPE_XSKMAP
- BPF_MAP_TYPE_SOCKHASH
- BPF_MAP_TYPE_CGROUP_STORAGE
- BPF_MAP_TYPE_REUSEPORT_SOCKARRAY
- BPF_MAP_TYPE_PERCPU_CGROUP_STORAGE
- BPF_MAP_TYPE_QUEUE
- BPF_MAP_TYPE_STACK
- BPF_MAP_TYPE_SK_STORAGE

たくさんあります．
しかし，BPF(XDP)を使う際によく使うマップはそんなに種類はなく,**太字**にしているものくらいだと思います．

- [BPF In Depth: Communicating with Userspace](https://blogs.oracle.com/linux/post/bpf-in-depth-communicating-with-userspace)
- [bpf(2) - Linux manual page - man7.org](https://man7.org/linux/man-pages/man2/bpf.2.html)

### ヘルパー関数
BPFマップの作成や参照，更新は[bpfシステムコール](https://man7.org/linux/man-pages/man2/bpf.2.html)を呼び出すことで行われます．
定義は以下です．
```c
int bpf(int cmd, union bpf_attr *attr, unsigned int size);
```
`linux/bpf.h`をインクルードすると使えるとのことですが，通常の環境では定義がありません．
そのためbpfシステムコールを直で使うのは結構大変です．

そこで，BPFマップの扱いを簡潔にする[ヘルパー関数](https://man7.org/linux/man-pages/man7/bpf-helpers.7.html)が用意されています．
マップの操作に限らず様々なヘルパー関数が定義されています．
ここでは頻繁に使用する関数のみ見ていきます．他の関数が気になる方は[man page](https://man7.org/linux/man-pages/man7/bpf-helpers.7.html)をのぞいてみてください．

#### マップ関連
- `void *bpf_map_lookup_elem(struct bpf_map *map, const void *key)`
	- keyに対応するvalueを探す
	- 値のポインタがNULLかチェックが必要
- ` long bpf_map_update_elem(struct bpf_map *map, const void *key, const void *value, u64 flags)`
	- keyに対応するvalueの値を更新する
	- flagsに渡す値によって値がすでに存在している場合の挙動などを指定する
	- `flags = 0`で新規に値を追加できる
- `long bpf_map_delete_elem(struct bpf_map *map, const void *key)`
	- keyに対応するエントリを削除する

#### デバッグ
- `long bpf_trace_printk(const char *fmt, u32 fmt_size, ...)`
	- デバッグのためにメッセージを出力する
	- `/sys/kernel/debug/tracing/trace_pipe`に出力されるので`cat`などで読む

#### XDPで使う
- `long bpf_fib_lookup(void *ctx, struct bpf_fib_lookup *params, int plen, u32 flags)`
	- FIB(Forwarding Information Base)(ルートテーブル)を参照することができる
	- [bpf_fib_lookup](https://elixir.bootlin.com/linux/latest/source/include/uapi/linux/bpf.h#L5947)という構造体を通してルートテーブルを参照して結果を得る
- `long bpf_xdp_adjust_head(struct xdp_buff *xdp_md, int delta)`
	- `xdp_md->data`で得られるパケットの先頭をずらすことができる
	- encap/decapに使用する

## Generic XDP
前項までで述べたようにXDPはNICのデバイスドライバレベルでパケットを処理します．
つまり，XDPが有効なNICでなければ使用することができません．
しかし，このような制限があると気軽にXDPを試すことができません．
そこでLinux Kernelには`Generic XDP`という機能がサポートされています．
この`Generic XDP`はXDPの強みである高速さを犠牲にして`sk_buff`の生成後にXDPプログラムを実行することができるようにしています．
そのため，NICのサポートの有無を気にすることなくXDPを試すことができます．

入門段階ではほぼすべてのケースで`Generic XDP`を使用することとなるため以降のサンプルでは`Generic XDP`を使用します．

`Generic XDP`の話題は[こちら](https://yunazuno.hatenablog.com/entry/2017/06/12/094101#f-609aae5d)の記事が詳しいので背景など気になる方はご覧ください．

## 実験環境
本記事での実験環境は以下のようになっています．
- AWS EC2 instance t3.large
- kernel version
	- 5.11.0-1019-aws
- architecture
	- x86_64
- NIC
	- Elastic Network Adaptor(ENA)
- os
	- Ubuntu 20.04.3 LTS
- clang
	- 10.0.0-4ubuntu
- iproute2
	- iproute2-ss200127
- go
	- go1.16.7 linux/amd64


## 使い方
XDPの使い方を紹介します．
XDPプログラムを実行するまでの手順は以下です．
1. XDPが有効なカーネルか確認し依存関係を解決する
2. C言語(制限付き)でXDPプログラムを記述する
3. `clang`でBPFバイトコードにコンパイル
4. カーネルにロードする

それぞれを詳しく見ていきましょう.

### XDPが有効なカーネルであるか確認, 依存関係の解決

#### XDPが有効なカーネルか確認
まずはカーネルのバージョンを確認します．
Generic XDPが使えるのは`4.12`以上です．

{{<x user="terassyi_" id="1217675419450634240">}}

このようなツイートもあるのでできるだけ最新に近いカーネルを使うのがよいと思います．
さらにカーネルのバージョンは要件を満たしていてもXDPを有効化してビルドされたものでなければ動かせません．
以下の設定が有効になっていることを確認します．
```
CONFIG_BPF=y
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_HAVE_EBPF_JIT=y
CONFIG_XDP_SOCKETS=y
```
これらの設定は以下のコマンドで確認します．
```shell
$ grep -i CONFIG_BPF /boot/config-$(uname -r)
$ grep -i CONFIG_XDP_SOCKETS /boot/config-$(uname -r)
```
その他詳しい機能のサポートバージョンなどは[How to compile a kernel with XDP support](https://medium.com/@christina.jacob.koikara/how-to-compile-a-kernel-with-xdp-support-c245ed3460f1)をご覧ください．

#### 依存関係の解決
依存関係のセットアップは[xdp tutorialのSetup dependencies](https://github.com/xdp-project/xdp-tutorial/blob/master/setup_dependencies.org)をご覧ください．
各ディストリビューションのインストールについて記載されています．

### NICの設定
`Generic XDP`を使用する場合はあまり気にする必要はないですが`Native XDP`(NICに実際にロードするXDP)を使用する場合mtuやqueueの問題でロードが失敗する可能性があります．
[本実験環境](#実験環境)では以下のコマンドで設定を変更することでNICにXDPをロードすることができました．

```shell
$ sudo ip link set dev ens5 mtu 3498
$ sudo ethtool -L ens5 combined 1
```

{{<x user="terassyi_" id="1446513432350519296">}}

### C言語(制限付き)でプログラムを記述する
C言語でプログラムを記述しますがBPFのプログラムは様々な制約があります．
主な制約は以下となっています．
- 命令数の制限
	- カーネルバージョン5.3以上で1M
- ループ制限
	- 無限ループは禁止
	- 5.2から有限ループは可能
- 到達不可能な命令があってはいけない
- 有効なメモリにのみアクセスできる
	- メモリが有効なものかチェックする必要がある

実際にプログラムを書く際の作法は[実践-BPF(XDP)用C言語のお作法](#bpf-xdp-用c言語のお作法)の項に記述しています．

BPFプログラムの制限に関する資料は以下を参照してください．
- [Introduction to eBPF and XDP](https://www.slideshare.net/lcplcp1/introduction-to-ebpf-and-xdp)
- [パケット処理の独自実装や高速化手法の比較と実践](https://www.janog.gr.jp/meeting/janog45/application/files/1615/7984/1029/008_pktfwd-xdp_kusakabe_00.pdf)

### `clang`でBPFバイトコードにコンパイルする
`example.c`を`example.o`に吐き出すコマンドは以下のような感じです．
```shell
$ clang -O2 -target bpf -c example.c -o example.o
```

### カーネルにロードする
コンパイルして生成されたELFファイルをカーネルにロードするすることによってXDPが実行されます．
ロードする方法はいくつか存在します．

#### iproute2
最も気軽に利用できるロード方法は`iproute2`を利用することです．
`iproute2`を利用する場合のロードは次のようにします．
```shell
$ ip link set dev ens5 xdp obj example.o
```
ロード後にNICの情報を見てみると以下のようにxdpプログラムがロードされています．
```
2: ens5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 3498 xdp qdisc mq state UP mode DEFAULT group default qlen 1000
    link/ether 0e:66:45:0d:d9:b9 brd ff:ff:ff:ff:ff:ff
    prog/xdp id 67
```
XDPプログラムを外す場合は以下のコマンドを実行します．
```shell
$ sudo ip link set dev ens5 xdp off
```

#### プログラムからロードする
BPFマップを利用するような複雑なXDPプログラムを実行したい場合，コントロールプレーンとしてプログラムを書く必要があります．
コントロールプレーンはどの言語でも特に問題ありません．
本記事ではコントロールプレーンのプログラムにはGo言語を使用します．

## 実践
本項ではXDPプログラムを実際に書いて動かしてみます．
Go言語でXDPのコントロールプレーンを記述するパッケージがいくつかあります．
- [cilium/ebpf](https://github.com/cilium/ebpf)
- [dropbox/goebpf](https://github.com/dropbox/goebpf)
- [iovisor/gobpf](https://github.com/iovisor/gobpf)

スターの数や開発状況などから見ても`cilium/ebpf`がデファクトといってよいと思います．
これからGo+XDPで開発を行うのであれば`cilium/ebpf`を使うのがよいでしょう．
一方で`dropbox/goebpf`はexamplesにxdpのサンプルがいくつかあり，基本的なプログラムを学ぶには非常によいと思います．
また，作りがシンプルなのでとっかかりやすいのではないかと思います．
`iovisor/gobpf`は使用したことがないのでわかりませんが`CGO`という話なのであまりお勧めとは言えません．

いくつかライブラリを紹介しましたが本記事では`cilium/ebpf`を使用してプログラムを記述します．

今回の実践編のサンプルコードは以下のリポジトリにあります．

{{<github repo="terassyi/go-xdp-examples">}}

> **2023/12/30 現在,cilium/ebpfの更新によりコントロールプレーンのコードも古くなってしまっています.**
> **現在のコントロールプレーンのコードは以下のリポジトリ(冒頭に挙げたコンテンツのリポジトリ)を参照したほうが最新の情報に近いです.**
> - [github.com/terassyi/seccamp-xdp/scmlb/pkg/loader/loader.go](https://github.com/terassyi/seccamp-xdp/blob/main/scmlb/pkg/loader/loader.go)

### BPF(XDP)用C言語のお作法
BPFバイトコードにコンパイルするC言語は様々な制約があると述べました．
本項ではその制約について具体的な例を示します．

#### 命令数の制約
カーネルバージョン5.3から命令数制限は1Mとなっているので現実的にこの制約が問題となることはないでしょう．
もし命令数制限を超えるBPFプログラムをロードしたいとき，複数のプログラムに分割，ロードするということになります．
これを実現するための手段として`bpf_tail_call()`, `BPF_MAP_TYPE_PROG_ARRAY`が用意されています．
詳しいドキュメントは[cilium document - tail-calls](https://docs.cilium.io/en/stable/bpf/#tail-calls)をご覧ください．

#### 無限ループ禁止
無限ループは禁止ですが有限ループは可能です．
XDPではパケットの改変を行うのでチェックサムの計算を行う機会も多いです．
IPチェックサムを計算する関数を例示します．
このコードは`bufsize`がいずれ必ず1以下となるので有効です．
```c
static inline __u16 checksum(__u16 *buf, __u32 bufsize) {
	__u32 sum = 0;
	while (bufsize > 1) {
		sum += *buf;
		buf++;
		bufsize -= 2;
	}
	if (bufsize == 1) {
		sum += *(__u8 *)buf;
	}
	sum = (sum & 0xffff) + (sum >> 16);
	sum = (sum & 0xffff) + (sum >> 16);
	return ~sum;
}
```

#### 有効なメモリにのみアクセスする
BPFプログラムではアクセスしたいメモリが有効であるか明示的にチェックした後でしかアクセスできません．
頻出する有効メモリチェックを二つ示します．

##### パケットのパース
ここで`data`はNICから受け取ったデータの先頭のポインタ．`data_end`は末尾のポインタです．
`ether`というethernetヘッダ用変数のポインタに`data`を代入してethernetヘッダをパースします．
このとき，ヘッダサイズが`data_end`を超えている場合無効なメモリにアクセスすることとなるので`data + sizeof(*ether) > data_end`であることを明示的にチェックしなければなりません．
```c
void *data_end = (void *)(long)ctx->data_end;
void *data = (void *)(long)ctx->data;
struct ethhdr *ether = data;
if (data + sizeof(*ether) > data_end) {
  return XDP_ABORTED;
}
```

##### BPFマップのlookup
BPFマップの参照は値が存在しなかった場合NULLとなります．
そのため，参照結果がNULLでないことをチェックしてから値を使用しなければなりません．
```c
__u32 *val = bpf_map_lookup_elem(&map, key);
if (!val) {
	return XDP_PASS;
}
```

#### 処理を関数に切り分けるときはinline展開する
XDPプログラム本体として実行される以外の自作関数はすべてinline展開される必要があります．
そのため，自作関数にはすべて`static inline`をつけましょう．
[無限ループ禁止](#無限ループ禁止)で例示したchecksum()関数を参考にしてください．

#### eBPF組み込み関数しか使えない
`memset()`, `memcpy()`といった関数はllvm組み込みの関数を使用することとなります．
```c
__builtin_memset((dest), (chr), (n))
__builtin_memcpy((dest), (src), (n))
__builtin_memmove((dest), (src), (n))
```
とはいえ引数は変わらないので気を付けていれば大丈夫です．

#### グローバル変数が~~使えない~~使える
~~グローバル変数は使用できません．~~
~~変わりに毎回BPFマップから値をとってくることとなります．~~

2019 年 にグローバル変数をサポートする[コミット](https://lore.kernel.org/bpf/20190228231829.11993-7-daniel@iogearbox.net/t/#u)が作成されています.
また,グローバル変数は[カーネルバージョン 5.5 から使える](https://github.com/falcosecurity/libs/blob/master/proposals/20220329-modern-bpf-probe.md#use-of-bpf-global-variables-kernel-version-55)ようです.
本記事執筆時点でも使えたようです.
誤情報を広めていました.
訂正します.

グローバル変数は内部的にはエントリ数 1 のマップが作成されているようです.

- [サンプルコード](https://github.com/terassyi/seccamp-xdp/blob/main/tutorial/counter.bpf.c#L11)


#### 可変長引数を取れない
可変長引数をとる関数を作成・使用することができません．
例として`bpf_printk(fmt, ...)`を見てみます．
`bpf_printk()`は`bpf_trace_printk()`を使いやすくラップした関数です．
定義は以下です．
```c
#define bpf_printk(fmt, ...)                                   \
  ({                                                           \
    char ____fmt[] = fmt;                                      \
    bpf_trace_printk(____fmt, sizeof(____fmt), ##__VA_ARGS__); \
  })
```
以下のように文字列を含めた5つの引数をとらせてみます．
```c
int test(struct xdp_md *ctx)
{
    int a, b, c, d = 0;
    bpf_printk("%d %d %d %d", a, b, c, d);
    return XDP_PASS;
}
```
```shell
$ clang -O2 -target bpf -c example.c -o example.o
example.c:9:5: error: too many args to 0xb70290: i64 = Constant<6>
int test(struct xdp_md *ctx)
    ^
1 error generated.
```
コンパイルすると`too many args`と怒られます．
これを4つ以下の引数にすると無事コンパイルは通ります．
MACアドレスなどをデバッグ出力したいときに非常に困りますが仕方ありません．気を付けましょう．


その他制約やコンパイル方法などは次のドキュメントが詳しいです．
- [cilium docs bpf #llvm](https://docs.cilium.io/en/stable/bpf/#llvm)

### チュートリアル
この項ではチュートリアルとして[dropbox/goebpf/examples/xdp](https://github.com/dropbox/goebpf/tree/master/examples/xdp)にあるサンプルを`cilium/ebpf`を用いて動かしてみるということを行います．

`dropbox/goebpf/examples/xdp`配下には
- packet_counter
- xdp_dump
- basic_firewall
- bpf_redirect_map

の4つのサンプルがあります．
こちらのC言語で書かれたXDPプログラムは基本的にそのまま使用します.(一部変更しなければ動作しないものがあるため変更します．)


#### 構成
まずディレクトリ構成について軽く述べます．

{{<github repo="terassyi/go-xdp-examples">}}

`/header/`配下に`bpf.h`, `bpf_helpers.h`を配置しています．これはBPFプログラムを記述するためのhelper関数などが定義されたヘッダファイルで，これらを使用することでBPFプログラム記述の負担が軽減されます．
今回配置しているのは`dropbox/goebpf/`に置いてあるものになっています．
様々なBPFプロジェクトが独自のヘッダファイルを使用している場合があり，微妙に定義が異なることもあるので注意してください．

各サンプルのディレクトリの中の`bpf/`配下にBPFプログラムを配置しています．
各サンプルのトップにはGoのプログラムが置いてあります．
ビルドなどはこのディレクトリで行います．

#### ビルド
ビルドに必要なステップは二つです．
```shell
$ go generate
$ go build .
```
`go generate`によって`bpf/`配下のC言語のコードをBPFバイトコードにコンパイルしてGoで扱うためのコードを自動生成します．
これは`bpf2go`([github.com/cilium/ebpf/cmd/bpf2go](https://github.com/cilium/ebpf/tree/master/cmd/bpf2go))というツールを使用しています．
`main.go`の中に`//go:generate`という感じで記述しておくことでコードを自動生成してくれます．
これが最初はとっつきにくいですが慣れると非常に便利です．

後は普通にビルドすることによってシングルバイナリとしてBPFのプログラムを扱うことができます．

#### packet_counter
`packet_counter`は指定されたNICが受信したパケットをプロトコルごとにカウントするプログラムです．
`main.go`と`bpf/xdp.c`から構成されます．
それぞれに分けてみていきます．

##### XDP
まずはXDPのコードから見ていきましょう．
最初はヘッダのインクルードと構造体の定義です．
`bpf_helpers.h`をインクルードします．
さらにパケットを表現する構造体を定義します．
しかし，これは`linux/if_ether.h`や`netinet/ip.h`などを使用してもかまいません．

続いてBPFマップを定義します．
packet_counterでは`BPF_MAP_TYPE_PERCPU_ARRAY`を定義しています．
```c
// eBPF map to store IP proto counters (tcp, udp, etc)
BPF_MAP_DEF(protocols) = {
    .map_type = BPF_MAP_TYPE_PERCPU_ARRAY,
    .key_size = sizeof(__u32),
    .value_size = sizeof(__u64),
    .max_entries = 255,
};
BPF_MAP_ADD(protocols);
```
keyは4byte, valueは8byteで定義しています．
続いてXDP関数です．
```c
SEC("xdp")
int packet_count(struct xdp_md *ctx) {
	...
}
```
`xdp`というセクション名を割り当てた関数がパケットの受信の度に呼び出されることとなります．
この関数は`xdp_md`という構造体を引数に取ります．
の構造体は受信したパケットなどの情報を保持したコンテキストです．
定義は[header/bpf_helpers.h](https://github.com/terassyi/go-xdp-examples/blob/master/header/bpf_helpers.h)にあり，以下のようになっています．
```c
struct xdp_md {
  __u32 data;
  __u32 data_end;
  __u32 data_meta;
  /* Below access go through struct xdp_rxq_info */
  __u32 ingress_ifindex; /* rxq->dev->ifindex */
  __u32 rx_queue_index;  /* rxq->queue_index  */

  __u32 egress_ifindex;  /* txq->dev->ifindex */
};
```
`data`が受信したパケットデータの先頭のポインタ，`data_end`がそのパケットデータの末尾のポインタとなっています．

それでは`packet_count`の中身を見ていきましょう．
パケットデータの先頭，末尾のポインタを移動させながらパケットをパースするのでそのための変数`data`, `data_end`を定義します．
```c
void *data_end = (void *)(long)ctx->data_end;
void *data = (void *)(long)ctx->data;
```
続いてethernetヘッダをパースします．
```c
struct ethhdr *ether = data;
if (data + sizeof(*ether) > data_end) {
  return XDP_ABORTED;
}
```
今回はIPv4プロトコルのみを扱うので`ether->h_proto`で分岐し，IPv4にマッチした場合のみ以下の処理を実行します．
`data`をethernetヘッダのサイズ分ずらすことでIPv4パケットの先頭にポインタを合わせてパースします．
その後，先ほど定義した`protocols`マップからIPプロトコルタイプをキーとして値を取り出しインクリメントすることでパケットをカウントします．
```c
if (ether->h_proto == 0x08U) {  // htons(ETH_P_IP) -> 0x08U
  data += sizeof(*ether);
  struct iphdr *ip = data;
  if (data + sizeof(*ip) > data_end) {
    return XDP_ABORTED;
  }
  // Increase counter in "protocols" eBPF map
  __u32 proto_index = ip->protocol;
  __u64 *counter = bpf_map_lookup_elem(&protocols, &proto_index);
  if (counter) {
    (*counter)++;
  }
}
```
最後にパケットをカーネルに流します．
```c
return XDP_PASS;
```

##### Go
続いてコントロールプレーンのコードを見ていきます．
`main.go`に
```
//go:generate go run github.com/cilium/ebpf/cmd/bpf2go -cc clang XdpProg ./bpf/xdp.c -- -I../header
```
と記述することによって`bpf2go`を`go generate`で使えるようにしています．

まずbpfプログラムとマップを保持する構造体を定義します．
```go
type Collect struct {
	Prog *ebpf.Program `ebpf:"packet_count"`
	Protocols *ebpf.Map `ebpf:"protocols"`
}
```
それでは`main`関数の処理を見ていきましょう．
コマンドライン引数からXDPプログラムをアタッチするインターフェース名を受け取り，そのインターフェースの情報を取得する処理を最初に行っています．
インターフェース情報の取得などは[vishvananda/netlink](https://github.com/vishvananda/netlink)を使用します．

前準備が終わると本命のXDP関連の処理となります．
`LoadXdpProg()`, `LoadAdnAssign()`は`bpf2go`から自動生成されるコードです．
自動生成されるコードについては今回は詳しく触れません．
`bpf2go`を実行する際に引数として渡す値に基づいて`Load<Name>()`生成されます．(今回の場合`XdpProg`という値を渡したので`LoadXdpProg()`)
この処理によってXDPのプログラムとマップをロードして`Collect`構造体にマッピングします．
```go
var collect = &Collect{}
spec, err := LoadXdpProg()
if err != nil {
	panic(err)
}
if err := spec.LoadAndAssign(collect, nil); err != nil {
	panic(err)
}
```
引き続いてNICへのアタッチです．
`cilium/ebpf`にはXDPをNICにアタッチするための関数は用意されていないのでnetlink経由でアタッチします．
netlinkにはXDPをアタッチする関数として[netlink.LinkSetXdpFd()](https://pkg.go.dev/github.com/vishvananda/netlink#LinkSetXdpFd)も用意されています．
今回は明示的に`Generic XDP`を指定してアタッチするために[netlink.LinkSetXdpFdWithFlags](https://pkg.go.dev/github.com/vishvananda/netlink#LinkSetXdpFdWithFlags)を使用しています．
基本的には`netlink.LinkSetXdpFd()`でアタッチして問題ありません．
こちらの記事([Generic XDPを使えばXDP動作環境がお手軽に構築できるようになった](https://yunazuno.hatenablog.com/entry/2017/06/12/094101#f-f6e9ed6b))にあるようにデフォルトでは`Native`, `Generic`の順にアタッチが試行されるようです．
以前`XDP_REDIRECT`を使用する際に明示的に`Generic XDP`を指定しなければパケット転送が動作しないというバグを踏んだことがあったため念のため明示的に`Generic XDP`を指定しています．
```go
if err := netlink.LinkSetXdpFdWithFlags(link, collect.Prog.FD(), nl.XDP_FLAGS_SKB_MODE); err != nil {
	panic(err)
}
defer func() {
	netlink.LinkSetXdpFdWithFlags(link, -1, nl.XDP_FLAGS_SKB_MODE)
}()
```
アタッチ関連の処理の後はXDPと連動したパケットカウント処理となります．
無限ループと`ticker`による1秒感覚の定期処理の中で以下のような処理を行います．
`collect.Protocols.Lookup()`でBPFマップから値を取り出します．
この時引数にkey, valueの変数のポインタを渡してあげる必要があります．
結果としてマップに値があれば`v`に値が格納されます．
keyに対応する値が存在していなくともerrorは返さないのでこのような記述となっています．
また，今回定義したBPFマップが`BPF_MAP_TYPE_PERCPU_ARRAY`なので`v`は`[]uint64`型です．
CPUごとにインデックスされて値が格納されるため，今回の実験環境では要素2のスライスとして値が格納されるのでこのような記述となっています．
```go
var v []uint64
var i uint32
for i = 0; i < 32; i++ {
	if err := collect.Protocols.Lookup(&i, &v); err != nil {
		panic(err)
	}
	if v[1] > 0 {
		fmt.Printf("%s : %v", getProtoName(i), v[1])
	} else if v[0] > 0 {
		fmt.Printf("%s : %v", getProtoName(i), v[0])
	}
}
```

以上で`packet_counter`は完成です．
パケットをカウントする単純な処理しかしていませんが基本的なXDPのアタッチやマップの定義，参照などは他のプロジェクトでも大体同じ感じです．

##### 実行
ビルドして実行してみます．
実験環境は`netns.sh`を使用して作成します．
ネットワーク構成は以下のような感じです．

![xdp-example-network-1](/img/xdp-example-network-1.png)

```shell
$ sudo ./netns.sh build
$ go generate
$ go build .
```
では動かしてみましょう．
XDPプログラムは`node1`のnetnsで動かします．
```shell
$ sudo ip netns exec node1 ./packet_counter -iface veth1
```
コンソールが返ってこなければ正常に起動しているはずです．
別のターミナルを起動して`veth1`のアドレス`192.168.0.2`に対して`ping`を飛ばしてみましょう．
```shell
$ ping -c 3 192.168.0.2
PING 192.168.0.2 (192.168.0.2) 56(84) bytes of data.
64 bytes from 192.168.0.2: icmp_seq=1 ttl=64 time=0.052 ms
64 bytes from 192.168.0.2: icmp_seq=2 ttl=64 time=0.050 ms
64 bytes from 192.168.0.2: icmp_seq=3 ttl=64 time=0.049 ms

--- 192.168.0.2 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2033ms
rtt min/avg/max/mdev = 0.049/0.050/0.052/0.001 ms
```
このように応答がかえってくるはずです．
では`packet_counter`の画面をみてみます．
```
IPPROTO_ICMP : 3
```
このようにICMPパケットが3つカウントされていることがわかります．
プロトコルごとにカウントするのでTCPやUDPでも試してみてください．

実験が終了したらnetnsの後片付けをしておきましょう．
```shell
$ sudo ./netns.sh clean
```

#### xdp_dump
`xdp_dump`はTCPパケットをキャプチャしてダンプするプログラムです．
`main.go`と`bpf/xdp_dump.c`から構成されます．
先ほどと同様にXDPとGoに分けてみていきましょう．

##### XDP
まずはXDPからです．
ヘッダのインクルードや構造体定義のやり方は[packet_counter](#xdp-2)と同様です．
今回は`BPF_MAP_TYPE_PERF_EVENT_ARRAY`を使用します．
```c
BPF_MAP_DEF(perfmap) = {
    .map_type = BPF_MAP_TYPE_PERF_EVENT_ARRAY,
    .max_entries = 128,
};
BPF_MAP_ADD(perfmap);
```
さらに`perf_event_item`という`perfmap`に格納する構造体を定義しておきます．
```c
struct perf_event_item {
  __u32 src_ip, dst_ip;
  __u16 src_port, dst_port;
};
```
続いてXDP関数の処理を見ていきます．
`xdp_dump`という名前で定義しています．
EthernetヘッダやIPv4ヘッダのパースは[packet_counter](#xdp-2)と同様です．
今回はTCPヘッダもパースするのでその処理を以下に抜粋します．
基本的にやり方は変わりませんが，IPv4ヘッダは可変長なので`ip->ihl * 4`でヘッダ長を計算して加算してあげる必要があります．
```c
data += ip->ihl * 4;
struct tcphdr *tcp = data;
if (data + sizeof(*tcp) > data_end) {
  return XDP_ABORTED;
}
```
その後は`SYN`フラグがついたパケットのみを対象としてperf eventを発火させます．
`packet_size`はあらかじめ`data - data_end`で求めています．
プログラム中のコメントにある通り，`flags`にはCPUのIDと`ctx(xdp_md struct)`の使用する範囲を指定した値をいれています．
```c
if (tcp->syn) {
  struct perf_event_item evt = {
    .src_ip = ip->saddr,
    .dst_ip = ip->daddr,
    .src_port = tcp->source,
    .dst_port = tcp->dest,
  };
  // flags for bpf_perf_event_output() actually contain 2 parts (each 32bit long):
  //
  // bits 0-31: either
  // - Just index in eBPF map
  // or
  // - "BPF_F_CURRENT_CPU" kernel will use current CPU_ID as eBPF map index
  //
  // bits 32-63: may be used to tell kernel to amend first N bytes
  // of original packet (ctx) to the end of the data.

  // So total perf event length will be sizeof(evt) + packet_size
  __u64 flags = BPF_F_CURRENT_CPU | (packet_size << 32);
  bpf_perf_event_output(ctx, &perfmap, flags, &evt, sizeof(evt));
}
```
その後は`XDP_PASS`して終了です．

##### Go
続いてGoのプログラムを見ていきます．
コマンドライン引数のパース，XDPプログラムやマップのロード，アタッチは[packet_counter](#xdp-2)と変わらないので省略して`perf event`の取り扱いを見ていきます．
XDP側で定義したものと同じフィールドを持つ`perfEventItem`構造体を定義しておきます．
```go
type perfEventItem struct {
	SrcIp uint32
	DstIp uint32
	SrcPort uint16
	DstPort uint16
}
```
次に`perf event`を読むためのReaderを生成します．
```go
perfEvent, err := perf.NewReader(collect.PerfMap, 4096)
```

`goroutine`で起動している部分が`perf event`をハンドリングする処理部です．
`perfEvent.Read()`でeventをpollして読み込みます．
無事読み込みが終了した場合`event.RawSample`に格納されたバイト列を`binary.Read()`で`perfEventItem`構造体にパースします．
さらに，`event.RawSample`が`perfEventItem`の大きさ(METADATA_SIZE = 12として定義している)よりも大きければパケットデータをダンプしてあげています．

```go
go func() {
	var event perfEventItem
	for {
		evnt, err := perfEvent.Read()
		if err != nil {
			if errors.Unwrap(err) == perf.ErrClosed {
				break
			}
			panic(err)
		}
		reader := bytes.NewReader(evnt.RawSample)
		if err := binary.Read(reader, binary.LittleEndian, &event); err != nil {
			panic(err)
		}
		fmt.Printf("TCP: %v:%d -> %v:%d\n",
			intToIpv4(event.SrcIp), ntohs(event.SrcPort),
			intToIpv4(event.DstIp), ntohs(event.DstPort),
		)
		if len(evnt.RawSample) - METADATA_SIZE > 0 {
			fmt.Println(hex.Dump(evnt.RawSample[METADATA_SIZE:]))
		}
		received += len(evnt.RawSample)
		lost += int(evnt.LostSamples)
	}
}()
```

`xdp_dump`では`perf event`を使用したためイベント駆動で処理することができました．

##### 実行
それでは動かしてみます．
今回も`netns.sh`で実験環境を作ってプログラムをビルドします．
```shell
$ go generate
$ go build .
$ sudo ./netns.sh build
```
続いて`node1`の中で`xdp_dump`を起動しましょう．
起動すると以下のようにTCPのSYNパケットを待ちます．
```shell
$ sudo ip netns exec node1 ./xdp_dump -iface veth1
All new TCP connection requests (SYN) coming to this host will be dumped here.

```
今回はTCPパケットを扱うので別のターミナルでpythonをつかってHTTPサーバを起動してそこにアクセスしてみます．
```shell
$ sudo ip netns exec node1 python3 -m http.server 8888
```
もう一つターミナルを開いて`curl`でHTTPサーバにアクセスしてみましょう．
```shell
$ curl http://192.168.0.2:8888
```
通常通りレスポンスが返ってくると思います．
また，`xdp_dump`を動かしているターミナルではTCP(SYN)パケットがダンプされていると思います．
```shell
All new TCP connection requests (SYN) coming to this host will be dumped here.

TCP: 192.168.0.3:43910 -> 192.168.0.2:8888
00000000  e2 f7 28 dc a0 65 12 4b  fe 5b 64 20 08 00 45 00  |..(..e.K.[d ..E.|
00000010  00 3c 93 c9 40 00 40 06  25 9d c0 a8 00 03 c0 a8  |.<..@.@.%.......|
00000020  00 02 ab 86 22 b8 9c 36  ba 88 00 00 00 00 a0 02  |...."..6........|
00000030  fa f0 81 84 00 00 02 04  05 b4 04 02 08 0a f4 c8  |................|
00000040  ac 0b 00 00 00 00 01 03  03 07 00 00 00 00 00 00  |................|
```

実験が終わったらnetnsを削除しておきましょう．

#### basic_firewall
3つめのサンプルは`basic_firewall`です．
IPv4ネットワークを入力として与えることで該当した宛先からのパケットをドロップします．
`basic_firewall`配下の`main.go`と`bpf/xdp_fw.c`から構成されます．
これまでと同様にXDPとGoに分けて見ていきましょう．

##### XDP
これまでのサンプルと同様にヘッダのインクルードと構造体の定義を行います．
その後BPFマップの定義を行います．
今回はふたつのマップを定義します．タイプはそれぞれ`BPF_MAP_TYPE_PERCPU_ARRAY`, `BPF_MAP_TYPE_LPM_TRIE`です．

`matches`は通常のArrayです．
入力したルール(IPv4ネットワーク)にマッチしたパケットをカウントするためのマップです．
```c
BPF_MAP_DEF(matches) = {
    .map_type = BPF_MAP_TYPE_PERCPU_ARRAY,
    .key_size = sizeof(__u32),
    .value_size = sizeof(__u64),
    .max_entries = MAX_RULES,
};
BPF_MAP_ADD(matches);
```

`blacklist`は入力されたルールを保持するマップです．
`lpm trie`という特殊なマップとして定義します．
`lpm trie`は[Longest Prefix Match with Trie Tree](https://www.lewuathe.com/longest-prefix-match-with-trie-tree.html)を意味しています．
ルートテーブルなどを作成する際に使用します．
IPv4アドレスとプレフィックスをキー，任意の値をバリューとして保存して使用します．

今回マップの定義にて`BPF_F_NO_PREALLOC`を指定しています．
`BPF_F_NO_PREALLOC`はプリアロケーションによるオーバーヘッドを削減するためのフラグです．
詳細は以下のリンクを参照してください．
- [Reduce pre-allocation overhead](https://pingcap.com/blog/tips-and-tricks-for-writing-linux-bpf-applications-with-libbpf#reduce-pre-allocation-overhead)

今回のサンプルではこのフラグを指定しなければBPFマップ作成が`Invalid argument`で失敗してしまいました．
これは[dropbox/goebpfのサンプル](https://github.com/dropbox/goebpf/blob/master/examples/xdp/basic_firewall/ebpf_prog/xdp_fw.c#L46)では指定されなくても動作していました．
一方今回`cilium/ebpf`を使用した際は与える必要がありました．
同様のエラーに遭遇した方は参考にしてください．

```c
BPF_MAP_DEF(blacklist) = {
    .map_type = BPF_MAP_TYPE_LPM_TRIE,
    .key_size = sizeof(__u64),
    .value_size = sizeof(__u32),
    .max_entries = MAX_RULES,
	.map_flags = BPF_F_NO_PREALLOC,
};
BPF_MAP_ADD(blacklist);
```

さて，マップの定義が終わったのでXDP関数の処理を見ていきます．今回は`firewall`という関数名です．
まずはこれまで通りEthernet, IPv4パケットのパースを行います．

その後，`blacklist`を参照するための`key`を作成します．
`key`はプレフィックスとアドレスのフィールドを持っています．

```c
struct {
  __u32 prefixlen;
  __u32 saddr;
} key;

key.prefixlen = 32;
key.saddr = ip->saddr;
```

以下がメインの処理部です．
先ほど用意した`key`で`blacklist`をlookupしてルールにマッチした場合`matches`からもカウンタを取り出してインクリメントしています．
その後，`XDP_DROP`を返すことでパケットをドロップします．
マッチしなかった場合は単に`XDP_PASS`を返します．

```c
__u64 *rule_idx = bpf_map_lookup_elem(&blacklist, &key);
if (rule_idx) {
  // Matched, increase match counter for matched "rule"
  __u32 index = *(__u32*)rule_idx;  // make verifier happy
  __u64 *counter = bpf_map_lookup_elem(&matches, &index);
  if (counter) {
    (*counter)++;
  }
  return XDP_DROP;
}
return XDP_PASS;
```

##### Go
次はコントロールプレーンを見ていきます．
コマンドライン引数のパースやXDPプログラムのロードとアタッチはこれまでと同様です．
今回は入力としてドロップするルールを渡します．
また，`lpm trie`を使用するので`lpmTrieKey`という型を用意しておきます．
```go
type lpmTrieKey struct {
	prefixlen uint32
	addr uint32
}
```

この型を使用して入力されたドロップルールを`blacklist`に挿入します．
```go
for index, ip := range ipList {
	fmt.Printf("\t%s\n", ip)
	k := ipNetToUint64(createLPMTrieKey(ip))
	if err := collect.Blacklist.Put(k, uint32(index)); err != nil {
		panic(err)
	}
}
```

以下はパケットのカウントを表示する部分です`packet_counter`で出てきたものとほぼ同じです．
`ticker`で定期的に処理しています．
```go
for {
	select {
	case <-ticker.C:
		var v []uint64
		var i uint32
		for i = 0; i < uint32(len(ipList)); i++ {
			if err := collect.Matches.Lookup(&i, &v); err != nil {
				panic(err)
			}
			if v[0] != 0 {
				fmt.Printf("%18s\t%d\n", ipList[i], v[0])
			} else if v[1] != 0 {
				fmt.Printf("%18s\t%d\n", ipList[i], v[1])
			}
		}
		fmt.Println()
	case <-ctrlC:
		fmt.Println("\nDetaching program and exit")
		return
	}
}
```

`basic_firewall`は`BPF_MAP_TYPE_LPM_TRIE`を利用することで簡単にIPアドレスがルールにマッチするかどうかを判断することができました．

##### 実行
それでは動かしてみます．
今回もこれまでと同様に`netns`で実験環境を用意します．
```shell
$ go generate
$ go build .
$ sudo ./netns.sh build
```
では`basic_firewall`を起動しましょう．今回は以下のように`192.168.0.0/24`をブロックするように指定して実行します．
```shell
$ sudo ip netns exec node1 ./basic_firewall -iface veth1 -drop 192.168.0.0/24
Blacklisting IPv4 Addresses...
        192.168.0.0/24

```
それでは別のターミナルから`ping`を飛ばしてみましょう．
`192.168.0.3 -> 192.168.0.2`向けのパケットが飛ぶはずなのでこれは`basic_firewall`を動かしている間はレスポンスがないはずです．
```shell
$ ping 192.168.0.2
```
というわけで`basic_firewall`を動かしているターミナルに戻ってみます．
```
Blacklisting IPv4 Addresses...
        192.168.0.0/24

    192.168.0.0/24      1

    192.168.0.0/24      2

    192.168.0.0/24      3

    192.168.0.0/24      4

    192.168.0.0/24      5
```
このようにブロックしたパケットをカウントして出力されています．
`Crtl + c`でプログラムを終了させると`ping`の応答が返ってくるようになることを確認してください．

実験が終了したら`netns`を掃除しておきましょう．

#### bpf_redirect_map
4つめのサンプルは`bpf_redirect_map`です．
このサンプルはICPMパケットを対象にICMPパケットの送信者にリダイレクトするというものとなっています．
`bpf_redirect_map`配下の`main.go`と`bpf/xdp.c`から構成されます．
これまでと同様にXDPとGoに分けて見ていきましょう．

##### XDP
これまでのサンプルと同様にヘッダのインクルードと構造体の定義を行います．
その後BPFマップの定義を行います．

今回は`BPF_MAP_TYPE_DEVMAP`というタイプのマップを使用します．
このマップは`bpf_redirect()`, `bpf_redirect_map()`を使用するためにデバイスのインデックスを保持しておくマップです．

こちらも少しハマりどころがあり，[dropbox/goebpfのサンプル](https://github.com/dropbox/goebpf/blob/master/examples/xdp/bpf_redirect_map/ebpf_prog/xdp.c#L44)では`max_entries`の値が`64`となっていますが`cilium/ebpf`を使用した場合マップに値を入れるときに`panic: update failed: key too big for map: argument list too long`と怒られます．
ですので今回は`1024`という大きめの数字を使用しています．

```c
/* XDP enabled TX ports for redirect map */
BPF_MAP_DEF(if_redirect) = {
    .map_type = BPF_MAP_TYPE_DEVMAP,
    .key_size = sizeof(__u32),
    .value_size = sizeof(__u32),
    .max_entries = 1024,
};
BPF_MAP_ADD(if_redirect);
```

次にXDP関数を見ていきます．
関数名は`xdp_test`です．
これまで通りEthernet, IPv4パケットにパースします．
さらに，IPパケットのプロトコルをみてICMPでなければPASSします．

続いて，ルートテーブルのlookup処理です．
XDPではカーネルのルートテーブルを参照することができます．
参照のためには
```c
static int (*bpf_fib_lookup)(void *ctx, void *params, int plen, __u32 flags) = (void*) // NOLINT
     BPF_FUNC_fib_lookup;
```
という関数を使用します．
この`bpf_fib_lookup()`に渡す`bpf_fib_lookup`構造体の定義について確認します．
```c
struct bpf_fib_lookup {
  /* input:  network family for lookup (AF_INET, AF_INET6)
  * output: network family of egress nexthop
  */
  __u8	family;

  /* set if lookup is to consider L4 data - e.g., FIB rules */
  __u8	l4_protocol;
  __be16	sport;
  __be16	dport;

  /* total length of packet from network header - used for MTU check */
  __u16	tot_len;

  /* input: L3 device index for lookup
  * output: device index from FIB lookup
  */
  __u32	ifindex;

  union {
    /* inputs to lookup */
    __u8	tos;		/* AF_INET  */
    __be32	flowinfo;	/* AF_INET6, flow_label + priority */

    /* output: metric of fib result (IPv4/IPv6 only) */
    __u32	rt_metric;
};

  union {
    __be32		ipv4_src;
    __u32		ipv6_src[4];  /* in6_addr; network order */
};

  /* input to bpf_fib_lookup, ipv{4,6}_dst is destination address in
  * network header. output: bpf_fib_lookup sets to gateway address
  * if FIB lookup returns gateway route
  */
  union {
    __be32		ipv4_dst;
    __u32		ipv6_dst[4];  /* in6_addr; network order */
};

  /* output */
  __be16	h_vlan_proto;
  __be16	h_vlan_TCI;
  __u8	smac[6];     /* ETH_ALEN */
  __u8	dmac[6];     /* ETH_ALEN */
};
```
ご覧のようにかなりいろいろなフィールドが定義されています．
しかし，単なるIPv4ルートテーブルを参照するだけであればそこまで大変ではありません．
セットするフィールドは以下です．
- family
- ipv4_src
- ipv4_dst
- ifindex

これらのフィールドをIPパケットとingressのifindexをもとにセットし，`bpf_fib_lookup()`に渡します．
その結果がfailedでなく`no neigh`でなければルートが引けたことになるのでその結果が引数として渡した`fib_params`に格納されます．

```c
struct bpf_fib_lookup fib_params;

// fill struct with zeroes, so we are sure no data is missing
__builtin_memset(&fib_params, 0, sizeof(fib_params));

fib_params.family	= AF_INET;
// use daddr as source in the lookup, so we refleect packet back (as if it wcame from us)
fib_params.ipv4_src	= ip_header->daddr;
// opposite here, the destination is the source of the icmp packet..remote end
fib_params.ipv4_dst	= ip_header->saddr;
fib_params.ifindex = ctx->ingress_ifindex;

bpf_printk("doing route lookup dst: %d\n", fib_params.ipv4_dst);
int rc = bpf_fib_lookup(ctx, &fib_params, sizeof(fib_params), 0);
if ((rc != BPF_FIB_LKUP_RET_SUCCESS) && (rc != BPF_FIB_LKUP_RET_NO_NEIGH)) {
    bpf_printk("Dropping packet\n");
    return XDP_DROP;
} else if (rc == BPF_FIB_LKUP_RET_NO_NEIGH) {
    // here we should let packet pass so we resolve arp.
    bpf_printk("Passing packet, lookup returned %d\n", BPF_FIB_LKUP_RET_NO_NEIGH);
    return XDP_PASS;
}
```

ルートが引けたらリダイレクト処理を行います．
IPパケットの宛先と送信元を入れ替えます．
さらに`fib_params`に格納された`dmac`と`smac`をパケットに上書きします．
そして，
```c
static int (*bpf_redirect_map)(void *map, __u32 key, __u64 flags) = (void*) // NOLINT
     BPF_FUNC_redirect_map;
```
を実行してリダイレクトします．
引数には定義したDEVMAPである`if_redirect`, それをlookupするキーとしてのifindex, flagは0です．

これによりICMPパケットを送信元にそのままリダイレクトします．

##### Go
続いてGoのコントロールプレーンをみていきます．
コマンドライン引数のパースやXDPプログラムのロードとアタッチはこれまでと同様です．
今回はNICを二つ引数として渡してあげます．
`bpf2go`で自動生成した関数を用いたプログラムのロードはれまでと同様です．
今回のリダイレクトのプログラムは二つのNICにアタッチしなければなりません．
さらに，アタッチするNICのインデックスを`DEVMAP`に登録する必要があります．
そこで以下のように`Attach()`関数を作成して上記の操作をまとめてしまいます．

```go
func Attach(infList []string, prog *ebpf.Program, ifRedirect *ebpf.Map) error {
	for _, inf := range infList {
		link, err := netlink.LinkByName(inf)
		if err != nil {
			return err
		}
		if err := netlink.LinkSetXdpFdWithFlags(link, prog.FD(), nl.XDP_FLAGS_SKB_MODE); err != nil {
			return err
		}
		if err := ifRedirect.Put(uint32(link.Attrs().Index), uint32(link.Attrs().Index)); err != nil {
			return err
		}
	}
	return nil
}
```

`Detach()`も同様に定義しておき`defer`に渡しておきます．
そのあとは`Ctrl + c`での終了処理を行うのみです．

```gov
if err := Attach(infList, collect.Prog, collect.IfRedirect); err != nil {
		panic(err)
}
defer Detach(infList)

ctrlC := make(chan os.Signal, 1)
signal.Notify(ctrlC, os.Interrupt)
for {
	select {
	case <-ctrlC:
		fmt.Println("\nDetaching program and exit")
		return
	}
}
```

##### 実行
それでは動かしてみましょう．
今回も`netns`で実験を行います．
```shell
$ go generate
$ go build .
$ sudo ./netns.sh build
```
それでは動かしてみます．
今回は以下のようにこれまでと少し異なる環境を用意しています．
![xdp-example-network-2.png](/img/xdp-example-network-2.png)

XDPプログラムは`node1`で`veth1`と`veth2`にアタッチします．
```shell
$ sudo ip netns exec node1 ./bpf_redirect_map -iflist veth1,veth2
```
コンソールが返ってこなければ正常に動作しています．
今回は特に何も出力してくれないので別ターミナルで`ping`と`tcpdump`を使って確認します．

それでは`192.168.1.5`に`ping`を飛ばしてみます．その様子を`tcpdump`で確認します．
```shell
$ ping -c 1 192.168.1.5
```
まずは`bpf_redirect_map`を動かさない状態でパケットを確認します．
###### bpf_redirect_mapなし
```shell
sudo tcpdump -i veth0 -n -vvv
tcpdump: listening on veth0, link-type EN10MB (Ethernet), capture size 262144 bytes
11:09:49.160300 IP (tos 0x0, ttl 64, id 19056, offset 0, flags [DF], proto ICMP (1), length 84)
    192.168.0.3 > 192.168.1.5: ICMP echo request, id 57, seq 1, length 64
11:09:49.160339 IP (tos 0x0, ttl 63, id 13495, offset 0, flags [none], proto ICMP (1), length 84)
    192.168.1.5 > 192.168.0.3: ICMP echo reply, id 57, seq 1, length 64
^C
2 packets captured
2 packets received by filter
0 packets dropped by kernel
```
このようにecho request, replyが一往復みられます．

つぎに`bpf_redirect_map`を動かした状態で同様に`ping`を飛ばしてみます．
```shell
$ sudo ip netns exec node1 ./bpf_redirect_map -iflist veth1,veth2
```
###### bpf_redirect_mapあり
```shell
sudo tcpdump -i veth0 -n -vvv
tcpdump: listening on veth0, link-type EN10MB (Ethernet), capture size 262144 bytes
11:13:10.304324 IP (tos 0x0, ttl 64, id 29369, offset 0, flags [DF], proto ICMP (1), length 84)
    192.168.0.3 > 192.168.1.5: ICMP echo request, id 58, seq 1, length 64
11:13:10.304357 IP (tos 0x0, ttl 64, id 29369, offset 0, flags [DF], proto ICMP (1), length 84)
    192.168.1.5 > 192.168.0.3: ICMP echo request, id 58, seq 1, length 64
11:13:10.304493 IP (tos 0x0, ttl 64, id 29370, offset 0, flags [none], proto ICMP (1), length 84)
    192.168.0.3 > 192.168.1.5: ICMP echo reply, id 58, seq 1, length 64
11:13:10.304500 IP (tos 0x0, ttl 64, id 29370, offset 0, flags [none], proto ICMP (1), length 84)
    192.168.1.5 > 192.168.0.3: ICMP echo reply, id 58, seq 1, length 64
^C
4 packets captured
4 packets received by filter
0 packets dropped by kernel
```
今度は4つパケットがキャプチャされています．
ICMPのIDをみてみるとどのパケットも58となっています．
一方で宛先と送信元が入れ替わっているパケットがみられます．

このようにNICからNICへのリダイレクト処理もXDPで行うことができます．

実験終了後には`netns`をお掃除しましょう．


## おわりに
今回はXDPに入門してみました．
だいぶ大作な記事になってしまいました．

XDPの概要やXDPを扱うために必要な周辺知識の紹介，実践編と段階的にXDPを理解できるように書きました．
結構ハマりどころが多い技術なので，私が勉強する際にハマった箇所はできるだけ書き起こしました．
XDP関連の日本語の記事はあまり多くないため参考になれば幸いです．

XDPでパケット処理しましょう．

## 参考

### 日本語
- [http://gundam-hathaway.net/mecha.html](http://gundam-hathaway.net/mecha.html)
- [Linuxカーネルの新機能 XDP (eXpress Data Path) を触ってみる](https://yunazuno.hatenablog.com/entry/2016/10/11/090245)
- [パケットフィルターでトレーシング？　Linuxで活用が進む「Berkeley Packet Filter（BPF）」とは何か](https://atmarkit.itmedia.co.jp/ait/articles/1811/21/news010.html)
- [XDPメモ（アーキテクチャ、性能、ユースケース）](https://blog.bobuhiro11.net/2020/09-17-xdp.html)
- [eXpress Data Path (XDP) の概要とLINEにおける利活用](https://speakerdeck.com/yunazuno/brief-summary-of-xdp-and-use-case-at-line)
- [パケット処理の独自実装や高速化手法の比較と実践](https://www.janog.gr.jp/meeting/janog45/application/files/1615/7984/1029/008_pktfwd-xdp_kusakabe_00.pdf)
- [転びながらもネットワーク処理をソフトウェアで自作していく話](https://speakerdeck.com/mabuchin/zhuan-binagaramonetutowakuchu-li-wo-sohutoueadezi-zuo-siteikuhua)
- [Generic XDPを使えばXDP動作環境がお手軽に構築できるようになった](https://yunazuno.hatenablog.com/entry/2017/06/12/094101)
- [今日から始めるXDPと取り巻く環境について](https://takeio.hatenablog.com/entry/2019/12/05/212945)
- [Go+XDPな開発を始めるときに参考になる記事/janog LT フォローアップ](https://takeio.hatenablog.com/entry/2021/01/26/180129)
- [ヘッダ構造体メモ](https://chipa34.hatenadiary.org/entry/20081217/1229479548)

### 英語
- [bpf(2) - Linux manual page - man7.org](https://man7.org/linux/man-pages/man2/bpf.2.html)
- [bpf-helpers(7) - Linux manual page - man7.org](https://man7.org/linux/man-pages/man7/bpf-helpers.7.html)
- [XDP - IO Visor Project](https://www.iovisor.org/technology/xdp)
- [A practical introduction to XDP](https://www.linuxplumbersconf.org/event/2/contributions/71/attachments/17/9/presentation-lpc2018-xdp-tutorial.pdf)
- [L4Drop: XDP DDoS Mitigations](https://blog.cloudflare.com/l4drop-xdp-ebpf-based-ddos-mitigations/)
- [Open-sourcing Katran, a scalable network load balancer](https://engineering.fb.com/2018/05/22/open-source/open-sourcing-katran-a-scalable-network-load-balancer/)
- [XDP Actions](https://prototype-kernel.readthedocs.io/en/latest/networking/XDP/implementation/xdp_actions.html)
- [BPF In Depth: Communicating with Userspace](https://blogs.oracle.com/linux/post/bpf-in-depth-communicating-with-userspace)
- [cilium docs bpf #llvm](https://docs.cilium.io/en/stable/bpf/#llvm)
- [How to compile a kernel with XDP support](https://medium.com/@christina.jacob.koikara/how-to-compile-a-kernel-with-xdp-support-c245ed3460f1)
- [Reduce pre-allocation overhead](https://pingcap.com/blog/tips-and-tricks-for-writing-linux-bpf-applications-with-libbpf#reduce-pre-allocation-overhead)
- [cilium/ebpf](https://github.com/cilium/ebpf)
- [dropbox/goebpf](https://github.com/dropbox/goebpf)
- [vishvananda/netlink](https://github.com/vishvananda/netlink)
