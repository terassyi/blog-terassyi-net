+++
categories = [ "tech" ]
tags = [ "network", "cni", "rust", "oss" ]
date = 2026-01-10
title = "RustのCNI Pluginライブラリを rscni をアップデートした"
description = "RustのCNI Pluginを作るためのライブラリ rscni を trait ベースの設計に作り替えました。"
+++

こんにちは。
葬送のフリーレン 3 期がはじまりますね。

今回は以前作った Rust の CNI Plugin ライブラリ [rscni](https://github.com/terassyi/rscni) を大幅に改修したので再度紹介します。

<!--more-->

{{<github repo="terassyi/rscni">}}

{{<crate-io crate="rscni">}}

rscni に関しては以前にこのブログで紹介しています。

- [RustのCNI Pluginライブラリを作った](https://blog.terassyi.net/posts/rscni/)

## 改修のモチベーション

rscni は自分が Rust で CNI プラグインを実装したかったために開発したライブラリです。せっかく作ったので後悔していましたが、ほとんどメンテしていませんでした。
その間に CNI spec v1.3 が公開されたりと、CNI 周りも動きがありました。

- [CNI spec v1.3](https://github.com/containernetworking/cni/blob/v1.3.0/SPEC.md)

そこで改めて実装を眺めてみると、Rust っぽくないインターフェースにムズムズし出したので、Trait を使って書き直して、ついでに CNI v1.3 に対応することにしました。

## CNI v1.0.0 から v1.3.0 の差分

rscni v0.0.4 がサポートしていたのは CNI spec v1.0.0 でした。2026/01 現在の CNI spec の最新バージョンは v1.3.0 です。このバージョン間での仕様変更を簡単に紹介すると以下のようになっています。

- `STATUS` コマンドの追加
  - プラグインが `ADD` コマンドを処理できる状態にあるかを検査するコマンド
- `GC` コマンドの追加
  - プラグインが不必要となった古いリソースを一括削除するためのコマンド
- `disableGC` フラグの追加
  - CNI 設定ファイルに `GC` コマンドをサポートするかどうかを指定するフラグ
- CNI Result 型へのいくつかのフィールド追加
  - 詳しくは仕様やリリースノートを確認してください

## rscni v0.2.1

さて、CNI spec v1.3.0 に対応し、Trait ベースの設計に再実装した rscni v0.2.1 をリリースしました。
詳細は [crates.io/crates/rscni](https://crates.io/crates/rscni) や [docs.rs/rscni](https://docs.rs/rscni/latest/rscni/) を見ていただきたいですが、ここで軽く利用方法を紹介します。

rscni は snyc/async 両方に対応しています。
async 機能は [async-trait](https://docs.rs/async-trait/latest/async_trait/) に依存しています。
(async trait の標準への取り込みは徐々に進んでいるようですが、まだ実用には時間がかかりそうです。)

せっかくなので今回は async 版で紹介しようと思います。

### Trait Definition

`Cni` trait は以下のような定義になっています。

```rust
pub trait Cni {
    // Required methods
    async fn add(&self, args: Args) -> Result<CNIResult, Error>;
    async fn del(&self, args: Args) -> Result<CNIResult, Error>;
    async fn check(&self, args: Args) -> Result<CNIResult, Error>;
    async fn status(&self, args: Args) -> Result<(), Error>;
    async fn gc(&self, args: Args) -> Result<(), Error>;
}
```

### 使い方

今回示す例は以下に全体のコードがあります。

- [github.com/terassyi/rscni/examples/async-rscni-debug](https://github.com/terassyi/rscni/blob/main/examples/async-rscni-debug/src/main.rs)

`Cni` trait を満たす型を以下のように実装すると、CNI プラグインとして振る舞うプログラムを作成できます。

```rust
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DebugConf {
    cni_output: PathBuf,
}

#[async_trait]
impl Cni for DebugConf {
    async fn add(&self, args: Args) -> Result<CNIResult, Error> {
        add(args).await
    }

    async fn del(&self, args: Args) -> Result<CNIResult, Error> {
        del(args).await
    }

    async fn check(&self, args: Args) -> Result<CNIResult, Error> {
        check(args).await
    }

    async fn status(&self, _args: Args) -> Result<(), Error> {
        Ok(())
    }

    async fn gc(&self, _args: Args) -> Result<(), Error> {
        // No cleanup needed for debug plugin
        Ok(())
    }
}
```

CNI プラグインのエントリーポイントとして振る舞うのは `Plugin` 構造体です。

```rust
#[derive(Debug, Default)]
pub struct Plugin {
    info: PluginInfo,
    msg: Option<String>,
}
```

Plugin 構造体を定義して、以下のように `run()` に `Cni` trait を満たした型を渡すと CNI プラグインとして振る舞います。

```rust
#[tokio::main]
async fn main() {
    let plugin = Plugin::default().msg(ABOUT_MSG);

    let debug_conf = DebugConf {
        cni_output: PathBuf::from(OUTPUT_FILE_PATH),
    };

    plugin
        .run(&debug_conf)
        .await
        .expect("Failed to complete the CNI call");
}
```

`run()` の実装は以下のようになっています。

```rust
    pub async fn run<T: Cni>(&self, cni: &T) -> Result<(), Error> {
        let res = self.inner_run::<T, OsEnv, StdIo>(cni).await?;

        StdIo::io_out()
            .write_all(res.as_bytes())
            .map_err(|e| Error::IOFailure(e.to_string()))
    }
```

## まとめ

Trait ベースの設計に再実装して、より Rust らしく CNI プラグインを実装できるようになったのではないでしょうか。
当の本人はまだこれを使って大したプラグインは作ってません。

そのうち作りたいものです。

Cloud Native 界隈は Kubernetes をはじめ、Go で実装されたソフトウェアが多いので、ぜひ Rust の勢力を伸ばしていきたいものです。その一助になるといいなぁ。
