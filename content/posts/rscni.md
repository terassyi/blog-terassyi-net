+++
categories = [ "tech" ]
tags = [ "network", "cni", "rust", "oss" ]
date = 2024-01-14
title = "RustのCNI Pluginライブラリを作った"
description = "RustのCNI Pluginを作るためのライブラリを作りました"
+++

こんにちは。
葬送のフリーレンが2クール連続で歓喜しています。

今回はRust用のCNI Pluginライブラリを作って公開したので紹介します。

## リポジトリとCrates.io

`rscni`という名前でGithub及びCrates.ioに公開しています。
ご興味のある方は使ってみてください。
バグ報告お待ちしています。

<!--more-->

{{<github repo="terassyi/rscni">}}

{{<crate-io crate="rscni">}}

## モチベーション

Rustでいい感じのCNI Plugin crateがなかったからです。
Rustの実装もあるにはあるのですが、2年ほど前に開発が止まってしまっていました。

{{<github repo="passcod/cni-plugins">}}

現在趣味でRustで[sart](https://github.com/terassyi/sart)というCNI Pluginを実装していて、このプロジェクトのためにしかたなく自作することにしました。
最初はcrateとして公開することはあまり考えていませんでしたが、複数プロジェクトに分けて開発しており、外部crateとして切り出してcrates.ioから利用できたほうが都合がよかったので公開することにしました。

CNIについては知っていて、`rscni`の使い方をさくっと知りたい方は[RsCNI](#rscni)に飛んでください。

{{<github repo="terassyi/sart">}}

## CNI

CNIはContainer Network Interfaceの略でコンテナのネットワークを設定するプラグインのための仕様とそのライブラリです。
[cni.dev](https://cni.dev)に情報がまとまっています。

CNIはあくまで仕様なので実際のCNIプラグインの実装は各プロジェクトによって様々です。
CNIが共通のインターフェースを提供することで、利用者は自身のユースケースに一番合ったCNIプラグインの実装を利用、もしくは自身で実装することができます。

代表的なCNIプラグインの実装は以下のようなものがあります。

- [Cilium](https://cilium.io)
- [Calico](https://www.tigera.io/project-calico/)
- [Flannel](https://github.com/flannel-io/flannel)

CNIはKubernetesに限らず様々ななプラットフォームで利用できますが、
本記事では現在最も一般的なCNIプラグインの利用先であろうKubernetesでの利用を前提として話を進めます。

### 実行形態

CNIプラグインは実行可能なバイナリファイルとして各Kubernetesノードに配置されます。
通常、各種プラグインは`/opt/cni/bin`に配置されます。

例えば、kindで作成したクラスターのノードには以下のように配置されています。
```
$ docker exec -it kind-control-plane ls -al /opt/cni/bin
total 14220
drwxrwxr-x 2 root root    4096 Mar 30  2023 .
drwxr-xr-x 3 root root    4096 Mar 30  2023 ..
-rwxr-xr-x 1 root root 3287319 Jan 16  2023 host-local
-rwxr-xr-x 1 root root 3353028 Jan 16  2023 loopback
-rwxr-xr-x 1 root root 3746163 Jan 16  2023 portmap
-rwxr-xr-x 1 root root 4161070 Jan 16  2023 ptp
```

これらのプラグインをどのように呼び出せばよいかを記述したファイルが同様に`/etc/cni/net.d`に配置されます。

kindの例では以下のようなファイルが配置されていました。

```
$ docker exec -it kind-control-plane ls /etc/cni/net.d
10-kindnet.conflist
$ docker exec -it kind-control-plane cat /etc/cni/net.d/10-kindnet.conflist
```

```json
{
  "cniVersion": "0.3.1",
  "name": "kindnet",
  "plugins": [
    {
      "type": "ptp",
      "ipMasq": false,
      "ipam": {
        "type": "host-local",
        "dataDir": "/run/cni-ipam-state",
        "routes": [
          {
            "dst": "0.0.0.0/0"
          }
        ],
        "ranges": [
          [
            {
              "subnet": "10.244.0.0/24"
            }
          ]
        ]
      },
      "mtu": 1500
    },
    {
      "type": "portmap",
      "capabilities": {
        "portMappings": true
      }
    },
  ]
}
```

Pod作成時にこの設定を見てkubeletがCNIプラグインを実行します。

以上のように実行可能なバイナリを配置し、設定に記述することで任意のCNIプラグインを実行させることができます。

### CNI Specification

CNIの仕様は[CNI Specification](https://www.cni.dev/docs/spec/)に定義されています。
いくつかのバージョンがあり、現在リリースされている最新バージョンは`v1.0.0`です。

詳細な仕様は原文を参照していただくとして、ここでは簡単に説明します。

この仕様書には以下のことが定義されています。

- システムの管理者が定義すべきネットワーク設定の構造
- コンテナランタイムがCNIプラグインを呼び出す際のプロトコル
- 設定に基づいてプラグインが実行すべき処理
- プラグインが他のプラグインに機能を委譲する際の処理
- プラグインが結果として返すべきデータの構造

#### ネットワーク設定ファイル

システム管理者が定義するネットワーク設定ファイルは上述した`/etc/cni/net.d`に配置されたファイルです。
[CNI Specification: Configuration format](https://www.cni.dev/docs/spec/#configuration-format)に詳細が記述されています。

`plugins`以下に実行したいプラグインの設定を定義します。

#### 実行プロトコル

詳細は[CNI Specification: Execution Protocol](https://www.cni.dev/docs/spec/#section-2-execution-protocol)を参照してください。

CNIプラグインはその役割から以下の２つのカテゴリに分けられます。

- Interface
	- コンテナ内のネットワークインターフェスを作成、設定する
- Chained
	- すでに作成されたネットワークインターフェースなどに対して任意の操作を行う

この2種類のプラグインをつなげて実行することでコンテナのネットワークを設定していきます。(いわゆるCNI Chainingです。)

##### パラメーター

CNIプラグインの実行時パラメーターは環境変数として渡されます。
以下のキーで値を取得して実行時に値を利用します。

- `CNI_COMMAND`
- `CNI_CONTAINERID`
- `CNI_NETNS`
- `CNI_IFNAME`
- `CNI_ARGS`
- `CNI_PATH`

その他に、任意のデータを標準入力からJSON形式で受け取ります。

#### オペレーション

CNIの仕様には`Add`, `Del`, `Check` and `Version`の4つのコマンドが定義されています。
どのコマンドを実行するかは`CNI_COMMAND`環境変数から取得します。

 - Add
	 - [CNI Specification: Add](https://www.cni.dev/docs/spec/#cni-operations)
	 - コンテナ作成時に実行されてインターフェースの作成や設定を行います
 - Del
	 - [CNI Specification: Del](https://www.cni.dev/docs/spec/#del-remove-container-from-network-or-un-apply-modifications)
	 - コンテナ削除時に実行されてインターフェースの削除などを行います
 - Check
	 - [CNI Specification: Check](https://www.cni.dev/docs/spec/#check-check-containers-networking-is-as-expected)
	 - ランタイムがコンテナが正常に設定されているかどうかを検査する際に実行され、コンテナの設定を検査します
 - Version
	 - [CNI Specification: Version](https://www.cni.dev/docs/spec/#version-probe-plugin-version-support)
	 - このプラグインがサポートするCNIバージョンを出力します


## RsCNI

Go言語でCNIプラグインを書く際、便利なライブラリとして[containernetworking/cni/pkg/skel](https://github.com/containernetworking/cni/tree/main/pkg/skel)が利用できます。
これはCNI Specificationと同一リポジトリで開発されているライブラリです。

以下のようなインターフェースで利用者が実装した処理の実体である関数(`cmdAdd`, `cmdDel`, `cmdCheck`)を渡すことでCNIプラグインとして振る舞えるように実装します。

```go
func PluginMain(cmdAdd, cmdCheck, cmdDel func(_ *CmdArgs) error, versionInfo version.PluginInfo, about string)
```

詳しくは以下を参照してください。

- [containernetwokring/cni/plugins/debug/main.go](https://github.com/containernetworking/cni/blob/main/plugins/debug/main.go#L41)

`rscni`はこのインターフェースを参考にして同じ書き味で書けるように実装しました。

以下が`rscni`の処理のエントリーポイントとなる構造体です。

```rust
pub struct Plugin {
    add: CmdFn,
    del: CmdFn,
    check: CmdFn,
    version_info: PluginInfo,
    about: String,
    dispatcher: Dispatcher,
}
```

この構造体に以下のように定義された`CmdFn`型を満たす関数を渡します。

```rust
pub type CmdFn = fn(args: Args) -> Result<CNIResult, Error>;
```

　全体像は以下のような感じです。
　
```rust
fn main() {
    let version_info = PluginInfo::default();
    let mut dispatcher = Plugin::new(add, del, check, version_info, ABOUT_MSG);

    dispatcher.run().expect("Failed to complete the CNI call");
}
```

### 使ってみる

参考実装として、`rscni-debug`という与えられた引数をファイルに出力するだけのCNIプラグインを`rscni`を使って実装しました。

- [github.com/terassyi/rscni/tree/main/examples](https://github.com/terassyi/rscni/tree/main/examples)

ところどころ省略していますが、このような形で書くことができます。

```rust
fn main() {
    let version_info = PluginInfo::default();
    let mut dispatcher = Plugin::new(add, del, check, version_info, ABOUT_MSG);

    dispatcher.run().expect("Failed to complete the CNI call");
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DebugConf {
    cni_output: PathBuf,
}

...

fn add(args: Args) -> Result<CNIResult, Error> {
    let cmd = "Add";
    let cni_output = output_args(cmd, &args)?;

    let net_conf = args.config.ok_or(Error::InvalidNetworkConfig(
        "cniOutput must be given".to_string(),
    ))?;
    let debug_conf = DebugConf::parse(&net_conf.custom)?;

    let mut file = debug_conf.open_file(&args.container_id, cmd)?;
    file.write(cni_output.as_bytes())
        .map_err(|e| Error::IOFailure(e.to_string()))?;

    Ok(match net_conf.prev_result {
        Some(prev) => prev,
        None => CNIResult::default(),
    })
}

fn del(args: Args) -> Result<CNIResult, Error> {
    let cmd = "Del";
    let cni_output = output_args(cmd, &args)?;

    let net_conf = args.config.ok_or(Error::InvalidNetworkConfig(
        "cniOutput must be given".to_string(),
    ))?;
    let debug_conf = DebugConf::parse(&net_conf.custom)?;

    let mut file = debug_conf.open_file(&args.container_id, cmd)?;
    file.write(cni_output.as_bytes())
        .map_err(|e| Error::IOFailure(e.to_string()))?;

    Ok(match net_conf.prev_result {
        Some(prev) => prev,
        None => CNIResult::default(),
    })
}

fn check(args: Args) -> Result<CNIResult, Error> {
    let cmd = "Check";
    let cni_output = output_args(cmd, &args)?;

    let net_conf = args.config.ok_or(Error::InvalidNetworkConfig(
        "cniOutput must be given".to_string(),
    ))?;
    let debug_conf = DebugConf::parse(&net_conf.custom)?;

    let mut file = debug_conf.open_file(&args.container_id, cmd)?;
    file.write(cni_output.as_bytes())
        .map_err(|e| Error::IOFailure(e.to_string()))?;

    Ok(match net_conf.prev_result {
        Some(prev) => prev,
        None => CNIResult::default(),
    })
}
```

では動かしてみます。

`examples/`に`Makefile`を用意していますので以下のように試すことができます。

ここではkindでKubernetesクラスターを作成して、ノード上にビルドした`rscni-debug`とそれを実行するように変更した設定ファイルをコピーしています。

```
$ # Build a rscni-debug binary
$ # Start kind cluster
$ # Copy netconf.json to the container
$ # Copy rscni-debug to the container
$ make start
cargo build --release --example rscni-debug
(snip)
    Finished release [optimized] target(s) in 5.25s
kind create cluster
Creating cluster "kind" ...
 ✓ Ensuring node image (kindest/node:v1.26.3) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-kind"
You can now use your cluster with:

kubectl cluster-info --context kind-kind

Thanks for using kind! 😊
docker cp ../target/release/examples//rscni-debug kind-control-plane:/opt/cni/bin/rscni-debug
Successfully copied 5.12MB to kind-control-plane:/opt/cni/bin/rscni-debug
docker cp ./netconf.json kind-control-plane:/etc/cni/net.d/01-rscni-debug.conflist
Successfully copied 2.56kB to kind-control-plane:/etc/cni/net.d/01-rscni-debug.conflist
$ # wait for creating some pods.
$ kubectl get pod -A
kubectl get pod -A
NAMESPACE            NAME                                         READY   STATUS    RESTARTS   AGE
kube-system          coredns-787d4945fb-7xrrd                     1/1     Running   0          116s
kube-system          coredns-787d4945fb-f4dk8                     1/1     Running   0          116s
kube-system          etcd-kind-control-plane                      1/1     Running   0          2m10s
kube-system          kindnet-2djjv                                1/1     Running   0          116s
kube-system          kube-apiserver-kind-control-plane            1/1     Running   0          2m13s
kube-system          kube-controller-manager-kind-control-plane   1/1     Running   0          2m10s
kube-system          kube-proxy-m7d4m                             1/1     Running   0          116s
kube-system          kube-scheduler-kind-control-plane            1/1     Running   0          2m10s
local-path-storage   local-path-provisioner-75f5b54ffd-42pzb      1/1     Running   0          116s
$ # exec into kind-control-plane
$ docker exec -it kind-control-plane bash
$ # list /tmp/cni
root@kind-control-plane:/# ls /tmp/cni
0a6a4b09df59d64e3be5cf662808076fee664447a1c90dd05a5d5588e2cd6b5a-Add  8f45a2e34dbca276cd15b3dc137eaa4f341ed3937404dca8fb7d7dbd47a860d1-Add
0a6a4b09df59d64e3be5cf662808076fee664447a1c90dd05a5d5588e2cd6b5a-Del  dc590314c1023d6ac95eafd08d09e71eb5eba7869ed38b1bad871f69ae5498a3-Add
1b9347ea59ae481b6a9a0bb6fecd12cfcd8b4ff0a05a1a21bf7c269663f99135-Add
$ # check the CNI output
root@kind-control-plane:/# cat /tmp/cni/0a6a4b09df59d64e3be5cf662808076fee664447a1c90dd05a5d5588e2cd6b5a-Add
CNI_COMMAND: Add
CNI_CONTAINERID: 0a6a4b09df59d64e3be5cf662808076fee664447a1c90dd05a5d5588e2cd6b5a
CNI_IFNAME: eth0
CNI_NETNS: Some("/var/run/netns/cni-8e9dfbc7-eaff-12a8-925e-4b280eb12d67")
CNI_PATH: ["/opt/cni/bin"]
CNI_ARGS: Some("K8S_POD_INFRA_CONTAINER_ID=0a6a4b09df59d64e3be5cf662808076fee664447a1c90dd05a5d5588e2cd6b5a;K8S_POD_UID=b0e1fc4a-f842-4ec2-8e23-8c0c8da7b5e5;IgnoreUnknown=1;K8S_POD_NAMESPACE=kube-system;K8S_POD_NAME=coredns-787d4945fb-7xrrd"),
STDIN_DATA: {"cniVersion":"0.3.1","name":"kindnet","type":"rscni-debug","prevResult":{"interfaces":[{"name":"veth3e00fda7","mac":"de:ba:bf:29:5a:80"},{"name":"eth0","mac":"fa:6f:76:59:25:82","sandbox":"/var/run/netns/cni-8e9dfbc7-eaff-12a8-925e-4b280eb12d67"}],"ips":[{"interface":1,"address":"10.244.0.3/24","gateway":"10.244.0.1"}],"routes":[{"dst":"0.0.0.0/0"}],"dns":{}},"cniOutput":"/tmp/cni"}
--------------------
```

作成したクラスター上Podが作成されると、このようにファイルが作成され、中身に呼び出し時の引数の値を出力していることがわかります。

## まとめ

`rscni`というRustのCNIプラグイン開発用ライブラリを作成して公開しました。
Go言語のライブラリを参考にして実装しました。

とりあえずライブラリとして使えるようになったので個人的に使っていこうと思います。

RustでCNIプラグインを実装することはほぼないと思いますが、使ってみてください。
