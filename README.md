![MornStorage](design/ogp.png)

# MornStorage

ディスクの使用量をツリーマップで表示するMacアプリ。macOS 14以降に対応しています。

## インストール

```bash
brew install --cask tsukumistudio/tap/mornstorage
```

更新はアプリ内の「更新を確認」、または次のコマンドで。

```bash
brew update
brew upgrade --cask mornstorage
```

アンインストール：

```bash
brew uninstall --cask mornstorage
```

## 使い方

初回は案内に従って「フルディスクアクセス」を許可してください。進めない場合は「再起動して確認」を押します。

「ボリュームを選択」でディスクを選び、「スキャン開始」を押します。起動時や選択時にはスキャンしません。
再スキャンは完了後、または中止の処理が終わってから行えます。

- タイルの面積はファイルの容量を表します。
- フォルダ名の後ろに合計容量を表示します。
- スキャン後にFinderなどで削除すると、表示とフォルダの容量も更新します。追加や容量の変化は再スキャンで反映します。
- フォルダをクリックすると中身を開閉できます。
- 右クリックでフォルダに注目したり、Finderで開いたりできます。「削除」は確認後にゴミ箱へ移動します。

## 開発

```bash
swift test
zsh build.sh  # dist/MornStorage.app
open dist/MornStorage.app
```

## ライセンス

[The Unlicense](LICENSE)
