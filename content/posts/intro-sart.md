+++
categories = [ "tech" ]
tags = [ "network", "kubernetes", "cni", "rust", "bgp", "loadbalancer", "oss" ]
date = 2024-04-12
title = "Kubernetes CNI plugin and network load balancer in Rust"
description = "Rustで CNI プラグインとロードバランサを作りました"
+++

こんにちは。

葬送のフリーレンのアニメが終了して途方に暮れています。
いいアニメでした。
続編に期待しています。

今回はしばらく趣味で開発している Kubernetes 用の CNI plugin とネットワークロードバランサ sart を紹介します。

リポジトリはこちらになります。
すべて Rust で実装しています。（e2e テストだけ Go 言語の Ginkgo を使っています。）

荒削りなソフトウェアですが、動かしてみたりスターをもらえると喜びます。（バグがたくさんありそう）

また、開発中のプロジェクトなので API の仕様が変更になる可能性は大いにあります。

<!--more-->

{{<github repo="terassyi/sart" >}}

## モチベーション

- 学習目的
    - Rust と Rust の非同期プログラミング
    - BGP
    - Kubernetes Network Load Balancer
    - CNI Plugin
- おうち Kubernetes クラスタを自分で実装したネットワークコンポーネントで構築したい

開発の動機は主に BGP や CNI、Kubernetes の LoadBalancer Service の仕組みを実装を通して知りたかったからです。

どうせ作るのであれば新規性を求めたいので Rust を選びました。

Rust も Rust の非同期プログラミングも初心者なので良くない実装も多々ありそうです。

また、おうち Kubernetes クラスタを自分で開発したソフトウェアで運用したいという密かな野望を秘めて開発しています。（クラスタ構築はこれからです。）

## Sart とは

開発している sart というソフトウェアは以下の機能を持っています。

- BGP
    - [RFC 4271](https://datatracker.ietf.org/doc/html/rfc4271) に沿って実装しています
- FIB コントローラー
    - BGP や他のプログラムと経路情報を送受信してカーネルの FIB(Forwarding Information Base) にインポート/エクスポートします
- CNI Plugin
    - [CNI Specification](https://github.com/containernetworking/cni/blob/v1.0.0/SPEC.md) に従って Interface plugin（正しい呼称ではないかも？） として機能します
- Kubernetes Network Load Balancer
    - [MetalLB](https://github.com/metallb/metallb) のように Kubernetes の [LoadBalancer Service](https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer) の VIP を管理・広報します

各機能について軽く紹介します。

### BGP

ルーティングプロトコルのひとつで Kubernetes でも Pod 間の疎通性の確保などに広く利用されています。

sart では [RFC 4271 -  A Border Gateway Protocol 4 (BGP-4)](https://datatracker.ietf.org/doc/html/rfc4271) に従って実装しています。

また、先行実装として [GoBGP](https://github.com/osrg/gobgp) や [RustyBGP](https://github.com/osrg/rustybgp) を参考にしました。

しかし、必要最低限の機能しか実装できておらず、使用できるユースケースは限定的です。

具体的な実装具合については以下を参照してください。

{{<github-preview repo="terassyi/sart" path="docs/design.md" lines="27-30">}}

将来的には再実装、もしくは外部ソフトウェアへの切りだしをしたいと思っています。


### FIB コントローラー

FIB コントローラーは BGP デーモンやその他プログラムとカーネルの経路データベースの間で経路情報を交換して実際にカーネルに経路を登録するプログラムです。

[FRR](https://frrouting.org/) の zebra や [Bird のルーティングテーブル機能](https://blog.cybozu.io/entry/bird)のような役割を担います。

こちらも最低限の機能しか実装できていません。

BGP と同様に将来的には再実装、もしくは外部ソフトウェアへの切りだしをしたいと思っています。


### CNI Plugin

Sart は Kubernetes 向けの CNI プラグインとして実装しています。

先行実装として [Coil](https://github.com/cybozu-go/coil) や [Cilium の Multi-Pool IPAM](https://docs.cilium.io/en/latest/network/concepts/ipam/multi-pool/) を参考に実装しました。

詳しくは後述しますが、Kubernetes のカスタムリソースベースの設定を与えて Pod に対して IP アドレスを割り当てることが可能となります。

また、一つのクラスタに複数の IP アドレス帯（Address Pool）を適用できるようになっています。

CNI プラグイン機能は BGP との連携を前提とした設計となっています。

### Network Load Balancer

Sart は Kubernetes 向けロードバランサ機能も有しています。

ここでのロードバランサとは、Kubernetes の LoadBalancer Service を管理するコンポーネントを指します。

先行実装として [MetalLB](https://metallb.universe.tf/) や [Cilium BGP Control Plane + LBIPAM](https://docs.cilium.io/en/latest/network/lb-ipam/#loadbalancer-ip-address-management-lb-ipam) があり、これらを参考にしています。

CNI プラグイン機能と同様に Kubernetes のカスタムリソースとして定義した Address Pool を利用して LoadBalancer 用 IP アドレスをクラスタに適用し、必要に応じてそれらを割り当てて外部に広報します。

外部への広報に関して、sart の BGP 機能を Kubernetes のカスタムリソースとして抽象化して利用しています。

## 使い方

ここでは Kind と [Containerlab](https://github.com/srl-labs/containerlab) を利用して BGP が使える Kubernetes クラスタを構築します。
余談ですが、Containerlab から直接 Kind クラスタを作れるようです。

この環境を動作させるためには Linux 環境が必要です。WSL2 では Containerlab でうまく環境を構築できないため動作しません。（Mac は動作未確認です。）

また、Rust が実行できる必要があります。

この実験環境は多くのコンテナを立ち上げるため、実行ホストのリソースに注意してください。

### 準備

まずは前準備でコンテナイメージのビルドと CRD マニフェストと Webhook 用証明書の生成を行います。
リポジトリの直下で以下のコマンドを実行してください。

```shell
$ make build-image # コンテナイメージのビルド
$ make certs # Kubernetes に必要な証明書の生成
$ make crd # CRD の生成
```

次に、実験用 Kubernetes クラスタを起動します。

```shell
$ cd e2e
$ make setup
$ make kubernetes MODE=cni
```

実験環境のトポロジーは以下のようになっています。

https://github.com/terassyi/sart/blob/main/e2e/README.md#cni

（CI 用に縮小版の環境も作成できます。その場合は `make kubernetes MODE=cni COMPACT=true`を実行してください。）

![kubernetes-cni-e2e-topology](/img/kubernetes-cni.png)

Kubernetes クラスタが起動したら、以下のように sart の CRD をクラスタに適用します。
Sart には CNI only, LB only, Dual の三つのモードを用意しています。
今回は dual モードで動作させます。

```shell
$ make install-sart MODE=dual
```

以下のように各 Deployment, Daemonset が起動していれば準備完了です。

```shell
$ kubectl -n kube-system get deploy sart-controller
NAME              READY   UP-TO-DATE   AVAILABLE   AGE
sart-controller   1/1     1            1           3m3s
$ kubectl -n kube-system get ds sartd-agent
NAME          DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
sartd-agent   4         4         4       4            4           kubernetes.io/os=linux   2m44s
$ kubectl -n kube-system get ds sartd-bgp
NAME        DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
sartd-bgp   4         4         4       4            4           kubernetes.io/os=linux   2m49s
```

これで準備が整いました。
これから実際にリソースを適用して動作を確かめていきます。

### BGP 関連リソースを作成する

Sart は前述の通り、BGP を扱う機能を Kubernetes のカスタムリソースとして抽象化しています。
BGP 関連リソースは以下のような構造になっています。

![kubernetes-cni-model](/img/kubernetes-cni-model.png)

トップレベルのリソースとして `ClusterBGP` と必要な場合は `BGPPeerTemplate` を作成します。
`ClusterBGP` は`.spec.nodeSelector` に基づいて対象ノードに対応した `NodeBGP` リソースを作成します。既に対象ノードに `NodeBGP` リソースが存在する場合は何もしません。

各対象ノードに対応する `NodeBGP` リソースが作成されたら、`ClusterBGP` リソースの `.spec.peers` に従って `BGPPeer` リソースを作成します。
`.spec.peers` に `peerTemplateRef` で `BGPPeerTemplate` リソースが指定されていた場合はそのリソースを基に、`BGPPeer` の spec が直接記述されていた場合はその spec を基に作成します。

この時、`BGPPeer` は各対象 `NodeBGP` リソースに対応して作成されます。
対象 `NodeBGP` リソースは `.spec.peers.[].nodeBGPSelector` に指定されたラベルにマッチしたものが選択されます。また、`NodeBGP` リソースのラベルは `Node` リソースのラベルから引き継がれます。

まずは `BGPPeerTemplate` リソースと `ClusterBGP` リソースを作成します。

この実験環境では各 Kubernetes ノードに直接接続している spine0 と spine1 に対してそれぞれ `BGPPeerTemplate` と `ClusterBGP` リソースを定義しています。

```yaml
apiVersion: sart.terassyi.net/v1alpha2
kind: BGPPeerTemplate
metadata:
  name: bgppeertemplate-spine0
spec:
  asn: 65001
  addr: 9.9.9.9
  groups:
    - to-spine0
---
apiVersion: sart.terassyi.net/v1alpha2
kind: BGPPeerTemplate
metadata:
  name: bgppeertemplate-spine1
spec:
  asn: 65002
  addr: 7.7.7.7
  groups:
    - to-spine1
```
```yaml
apiVersion: sart.terassyi.net/v1alpha2
kind: ClusterBGP
metadata:
  name: clusterbgp-spine0
spec:
  nodeSelector:
    bgp: a
  asnSelector:
    from: label
  routerIdSelector:
    from: internalAddress
  speaker:
    path: 127.0.0.1:5000
    multipath: true
  peers:
    - peerTemplateRef: bgppeertemplate-spine0
      nodeBGPSelector:
        bgp: a
```
```yaml
apiVersion: sart.terassyi.net/v1alpha2
kind: ClusterBGP
metadata:
  name: clusterbgp-spine1
spec:
  nodeSelector:
    bgp: a
  asnSelector:
    from: label
  routerIdSelector:
    from: internalAddress
  speaker:
    path: 127.0.0.1:5000
    multipath: true
  peers:
    - peerTemplateRef: bgppeertemplate-spine1
      nodeBGPSelector:
        bgp: a
```

これらを順次適用すると自動的に BGPPeer リソース作成され、が各ノード上の `sartd-bgp` と `spine0` と `spine1` の FRR と BGP セッションが確立されます。

```shell
$ kubectl apply -f ../manifests/cni/sample/peer_template.yaml
bgppeertemplate.sart.terassyi.net/bgppeertemplate-spine0 created
bgppeertemplate.sart.terassyi.net/bgppeertemplate-spine1 created
$ kubectl apply -f ../manifests/cni/sample/cluster_bgp_spine0.yaml
clusterbgp.sart.terassyi.net/clusterbgp-spine0 created
$ kubectl apply -f ../manifests/cni/sample/cluster_bgp_spine1.yaml
clusterbgp.sart.terassyi.net/clusterbgp-spine1 created
```

```shell
$ kubectl get bgppeer
NAME                                                      ASN     ADDRESS   NODEBGP              CLUSTERBGP          BACKOFF   STATUS        AGE
bgppeertemplate-spine0-sart-control-plane-65001-9.9.9.9   65001   9.9.9.9   sart-control-plane   clusterbgp-spine0   0         Established   50s
bgppeertemplate-spine0-sart-worker-65001-9.9.9.9          65001   9.9.9.9   sart-worker          clusterbgp-spine0   0         Established   50s
bgppeertemplate-spine0-sart-worker2-65001-9.9.9.9         65001   9.9.9.9   sart-worker2         clusterbgp-spine0   0         Established   50s
bgppeertemplate-spine0-sart-worker3-65001-9.9.9.9         65001   9.9.9.9   sart-worker3         clusterbgp-spine0   0         Established   50s
bgppeertemplate-spine1-sart-control-plane-65002-7.7.7.7   65002   7.7.7.7   sart-control-plane   clusterbgp-spine1   0         Established   35s
bgppeertemplate-spine1-sart-worker-65002-7.7.7.7          65002   7.7.7.7   sart-worker          clusterbgp-spine1   0         Established   25s
bgppeertemplate-spine1-sart-worker2-65002-7.7.7.7         65002   7.7.7.7   sart-worker2         clusterbgp-spine1   0         Established   15s
bgppeertemplate-spine1-sart-worker3-65002-7.7.7.7         65002   7.7.7.7   sart-worker3         clusterbgp-spine1   0         Established   5s
```

以上のようにすべての `BGPPeer` リソースのステータスが `Established` になっていれば完了です。

後述の `AddressBlock` リソースの作成や LoadBalancer Service の作成により適宜 `BGPAdvertisement` リソースが作成され、対象の `BGPPeer` リソースに対応した sartd-bgp の BGP セッションが指定された経路を広報します。

### Pod 用 Address Pool を作成する

BGP 関連リソースの適用が完了したら、Pod 用の Address Pool を作成します。

`AddresssPool` リソースを作成してクラスタに Address Pool を適用できます。

Sart は一つのクラスタに複数の `AddressPool` リソースを適用できます。

複数の `AddressPool` リソースが一つのクラスタに存在するとき、sart は `AddressPool` の `.spec.autoAssign` をみて、true となっている Address Pool を選択してアドレスを割り当てます。（`autoAssign=true` な `AddressPool` リソースはクラスタに一つしか作成できません。）

Sart は 一つの `AddressPool` リソースを `AddressBlock` リソースという単位に分割して管理します。

`.spec.blockSize` はその Address Pool をどのくらいの大きさで分割するかの単位です。

実験環境では以下の２つの `AddressPool` を適用します。

```yaml
apiVersion: sart.terassyi.net/v1alpha2
kind: AddressPool
metadata:
  name: default-pod-pool
spec:
  cidr: 10.1.0.0/24
  type: pod
  allocType: bit
  blockSize: 29
  autoAssign: true
---
apiVersion: sart.terassyi.net/v1alpha2
kind: AddressPool
metadata:
  name: non-default-pod-pool
spec:
  cidr: 10.10.0.0/29
  type: pod
  allocType: bit
  blockSize: 32
  autoAssign: false
```

```shell
$ kubectl apply -f ../manifests/cni/sample/pool.yaml
addresspool.sart.terassyi.net/default-pod-pool created
addresspool.sart.terassyi.net/non-default-pod-pool created
```

### Pod を作成する

これまでで Pod を作成する準備ができました。
ここではテスト用に用意したマニフェストで Pod を作成します。

```shell
$ kubectl apply -f ../manifests/cni/sample/namespace.yaml
namespace/test created
$ kubectl apply -f ../manifests/cni/sample/test_pod.yaml
pod/test-cp created
pod/test-worker created
pod/test-worker2 created
pod/test-worker3 created
pod/test-worker3-2 created
```

この例では各ノード上に Pod を作成しています。
以下のように各 Pod に対して IP アドレスが割り当てられ、`Running` になっていれば CNI プラグインとして正常に動作しています。

```shell
$ kubectl -n test get pod -owide
NAME             READY   STATUS    RESTARTS   AGE   IP          NODE                 NOMINATED NODE   READINESS GATES
test-cp          1/1     Running   0          60s   10.1.0.9    sart-control-plane   <none>           <none>
test-worker      1/1     Running   0          60s   10.1.0.0    sart-worker          <none>           <none>
test-worker2     1/1     Running   0          60s   10.1.0.24   sart-worker2         <none>           <none>
test-worker3     1/1     Running   0          60s   10.1.0.16   sart-worker3         <none>           <none>
test-worker3-2   1/1     Running   0          60s   10.1.0.17   sart-worker3         <none>           <none>
```

この Pod の作成で各ノードごとに `AddressBlock` リソースが作成され、それに対応して `BGPAdvertisement` リソースが作成されます。

```shell
$ kubectl get addressblock
NAME                     CIDR            TYPE      POOLREF                NODEREF              AGE
default-lb-pool          10.0.1.0/24     service   default-lb-pool        <no value>           4m38s
default-pod-pool-0       10.1.0.0/29     pod       default-pod-pool       sart-control-plane   7m24s
default-pod-pool-1       10.1.0.8/29     pod       default-pod-pool       sart-worker          7m24s
default-pod-pool-2       10.1.0.16/29    pod       default-pod-pool       sart-worker3         7m23s
default-pod-pool-3       10.1.0.24/29    pod       default-pod-pool       sart-worker2         7m23s
```

```shell
$ kubectl get bgpadvertisement -n kube-system
NAME                     CIDR           TYPE   PROTOCOL   AGE
default-pod-pool-0       10.1.0.0/29    pod    ipv4       8m7s
default-pod-pool-1       10.1.0.8/29    pod    ipv4       8m7s
default-pod-pool-2       10.1.0.16/29   pod    ipv4       8m7s
default-pod-pool-3       10.1.0.24/29   pod    ipv4       8m7s
```

最後に各 Pod 間で疎通が取れることを確かめます。
適当な Pod から他の適当な Pod のアドレスに対して ping を実行します。

以下のように応答が返ってくれば問題なく経路広報やネットワークの設定が完了していることがわかります。

```shell
$ kubectl -n test exec -it test-cp -- ping -c 1 10.1.0.24
PING 10.1.0.24 (10.1.0.24) 56(84) bytes of data.
64 bytes from 10.1.0.24: icmp_seq=1 ttl=61 time=0.223 ms

--- 10.1.0.24 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 0.223/0.223/0.223/0.000 ms
```

### Address Pool を選択して Pod を作成する

前述の通り、sart は複数の `AddressPool` を作成して利用できます。

それらの `AddressPool` リソースの `.spec.autoAssign=true` （デフォルト）でない Address Pool を利用して Pod を作成したい場合は Pod のマニフェストに `sart.terassyi.net/addresspool: <pool name>` という annotation を付与します。

また、一つ一つの Pod に annotation をつけて作成するのは大変なので `Namespace` に対して同じ annotation を付与すればその `Namespace` に作成される Pod すべてが指定した Address Pool を利用できます。

以下のマニフェストを適用してみます。

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: test-non-default
  labels:
    name: test
  annotations:
    sart.terassyi.net/addresspool: non-default-pod-pool
---
apiVersion: v1
kind: Pod
metadata:
  name: test-worker2-non-default
  namespace: test-non-default
spec:
  containers:
  - name: test-non-default
    image: ghcr.io/terassyi/test-server:0.1.2
  nodeSelector:
    kubernetes.io/hostname: sart-worker2
---
apiVersion: v1
kind: Pod
metadata:
  name: test-worker3-non-default
  namespace: test-non-default
spec:
  containers:
  - name: test
    image: ghcr.io/terassyi/test-server:0.1.2
  nodeSelector:
    kubernetes.io/hostname: sart-worker3
```

```shell
$ kubectl apply -f ../manifests/cni/sample/test_pod_in_namespace.yaml
namespace/test-non-default created
pod/test-worker2-non-default created
pod/test-worker3-non-default created
```

新たに作成した `test-non-default`  Namespace の Pod を取得すると `non-default-pod-pool` のアドレスの範囲（10.10.0.0/29）から Pod にアドレスが割り当てられています。

```shell
$ kubectl -n test-non-default get pod -owide
NAME                       READY   STATUS    RESTARTS   AGE   IP          NODE           NOMINATED NODE   READINESS GATES
test-worker2-non-default   1/1     Running   0          33s   10.10.0.0   sart-worker2   <none>           <none>
test-worker3-non-default   1/1     Running   0          33s   10.10.0.1   sart-worker3   <none>           <none>
```

最後に各 Pod 間の疎通性を確かめます。

以下のように `test/test-cp` から `test-non-default/test-worker3-non-default` に対して疎通が確認できます。

```shell
kubectl -n test exec -it test-cp -- ping -c 1 10.10.0.1
PING 10.10.0.1 (10.10.0.1) 56(84) bytes of data.
64 bytes from 10.10.0.1: icmp_seq=1 ttl=61 time=0.167 ms

--- 10.10.0.1 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 0.167/0.167/0.167/0.000 ms
```

以上が CNI プラグインとしての sart の機能となります。

### LoadBalancer Service 用 Address Pool を作成する

Sart は Network Load Balancer 機能も実装しています。

この機能を利用するためには、CNI プラグイン機能の場合と同様に `AddressPool` リソースを作成します。

異なるのは `.spec.type` に `service` を指定する点です。

以下のマニフェストを適用します。

```yaml
apiVersion: sart.terassyi.net/v1alpha2
kind: AddressPool
metadata:
  name: default-lb-pool
spec:
  cidr: 10.0.1.0/24
  type: service
  allocType: bit
  autoAssign: true
---
apiVersion: sart.terassyi.net/v1alpha2
kind: AddressPool
metadata:
  name: non-default-lb-pool
spec:
  cidr: 10.0.100.0/24
  type: service
  allocType: bit
  blockSize: 24
  autoAssign: false
```

```shell
$ kubectl apply -f ../manifests/lb/sample/lb_address_pool.yaml
addresspool.sart.terassyi.net/default-lb-pool created
addresspool.sart.terassyi.net/non-default-lb-pool created
$ kubectl get addresspool
NAME                  CIDR            TYPE      BLOCKSIZE   AUTO    AGE
default-lb-pool       10.0.1.0/24     service               true    51s
non-default-lb-pool   10.0.100.0/24   service   24          false   51s
```

以上のように `service`タイプの Address Pool が作成されます。

作成された `service`タイプの Address Pool にも auto assign の設定が存在します。

後述しますが、annotation を用いて利用したい Address Pool を選択できます。

### LoadBalancer を作成する

Address Pool の作成が完了したので LoadBalancer service を作成します。

以下のマニフェストを適用します。

このマニフェストはいくつかの LoadBalancer service とバックエンドとなる Deployment を作成します。

それぞれ以下のような特徴を持っています

- app-svc-cluster
    - externalTrafficPolicy=Cluster
    - default-lb-pool を利用（指定なし）
- app-svc-local
    - externalTrafficPolicy=Local
    - default-lb-pool を利用（指定なし）
- app-svc-cluster2
    - externalTrafficPolicy=Cluster
    - non-default-lb-pool を利用（annotation で指定）
    - 利用アドレスを annotation で指定

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: test
  labels:
    name: test
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-cluster
  namespace: test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app-cluster
  template:
    metadata:
      labels:
        app: app-cluster
    spec:
      containers:
        - name: app
          image: nginx:latest
          ports:
            - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-local
  namespace: test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app-local
  template:
    metadata:
      labels:
        app: app-local
    spec:
      containers:
        - name: app
          image: nginx:latest
          ports:
            - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-cluster2
  namespace: test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app-cluster2
  template:
    metadata:
      labels:
        app: app-cluster2
    spec:
      containers:
        - name: app
          image: nginx:latest
          ports:
            - containerPort: 80
---
# LoadBalancer Service
apiVersion: v1
kind: Service
metadata:
  name: app-svc-cluster
  namespace: test
  annotations:
spec:
  type: LoadBalancer
  externalTrafficPolicy: Cluster
  selector:
    app: app-cluster
  ports:
    - name: http
      port: 80
      targetPort: 80
---
# LoadBalancer Service
apiVersion: v1
kind: Service
metadata:
  name: app-svc-local
  namespace: test
  annotations:
    sart.terassyi.net/addresspool: default-lb-pool
spec:
  type: LoadBalancer
  externalTrafficPolicy: Local
  selector:
    app: app-local
  ports:
    - name: http
      port: 80
      targetPort: 80
---
# LoadBalancer Service
apiVersion: v1
kind: Service
metadata:
  name: app-svc-cluster2
  namespace: test
  annotations:
    sart.terassyi.net/addresspool: non-default-lb-pool
    sart.terassyi.net/loadBalancerIPs: "10.0.100.20"
spec:
  type: LoadBalancer
  externalTrafficPolicy: Cluster
  selector:
    app: app-cluster2
  ports:
    - name: http
      port: 80
      targetPort: 80
```

```shell
$ kubectl apply -f .../manifests/lb/sample/lb.yaml
namespace/test created
deployment.apps/app-cluster created
deployment.apps/app-local created
deployment.apps/app-cluster2 created
service/app-svc-cluster created
service/app-svc-local created
service/app-svc-cluster2 created
```

適用後、以下のように `Service` リソースが作成され、 `EXTERNAL-IP` フィールドが利用している Address Pool から割り当てられたアドレスとなっていることが確認できます。

`app-svc-cluster2` に関してはマニフェストで指定したアドレスが割り当てられています。

```shell
kubectl -n test get svc
NAME               TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
app-svc-cluster    LoadBalancer   10.101.145.245   10.0.1.0      80:30707/TCP   9m59s
app-svc-cluster2   LoadBalancer   10.101.138.237   10.0.100.20   80:32524/TCP   9m59s
app-svc-local      LoadBalancer   10.101.38.67     10.0.1.1      80:31691/TCP   9m59s
```

最後にこれらの LoadBalancer Service に疎通確認を行います。

以下のように `clab-sart-client0` というコンテナから各アドレスに対して curl を実行して確認します。

```shell
$ docker exec -it clab-sart-client0 curl http://10.0.1.0
{"timestamp":"2024-04-08T14:17:58.127992327Z","from":"10.1.0.25","to":"172.18.0.3:18363"}
$ docker exec -it clab-sart-client0 curl http://10.0.1.1
{"timestamp":"2024-04-08T14:19:41.048009684Z","from":"10.1.0.26","to":"192.168.0.2:56018"}%
$ docker exec -it clab-sart-client0 curl http://10.0.100.20
{"timestamp":"2024-04-08T14:19:52.551894221Z","from":"10.1.0.12","to":"172.18.0.5:64839"}%
```

当然ではありますが、`externalTrafficPolicy` は `Local`, `Cluster` 両方に対応しています。
test 用サーバからのレスポンスでどの Pod から返ってきているか、`externalTrafficPolicy=Cluster` の場合はどのノードを経由しているかが確認できます。

### 補足

これらの動作確認は e2e テストで確認しているものとほぼ同一です。

一気に流すには以下のコマンドを実行してください。

```shell
$ make kubernetes MODE=cni # 環境作成
$ make install-sart MODE=cni # 準備
$ make cni-e2e # e2e テスト
$ make kubernetes-down MODE=cni # 環境削除
```

## まとめ

本記事では Rust で自作している CNI プラグインの使い方を紹介しました。

本当は設計や実装も併せて紹介したいところでしたがかなり長くなるので今回は利用方法のみにしました。

このプロジェクトのために BGP から独自実装したり [CNI プラグインライブラリを自作した](https://terassyi.net/posts/2024/01/14/rscni.html)のでどこかで実装の詳細についても紹介の機会を設けたいです。

設計などのドキュメントは[リポジトリの /docs](https://github.com/terassyi/sart/blob/main/docs/design.md) 以下に拙い英語でまとまっています。

さて、これからですが、まずは自宅で Kubernetes クラスタを構築してそこに sart を導入して運用していきたいです。

そのうえで必要な機能拡張やログの整理などをやっていければよいかなと思っています。

この記事を読んだ方が動かして遊んでみてもらえると嬉しいなと思います。
