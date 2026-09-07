# MornStorage

ディスク使用量をツリーマップで可視化する Mac アプリです (SpaceSniffer 風)。
macOS 14 以降対応。

## Homebrew での導入

```bash
brew install --cask tsukumistudio/tap/mornstorage
```

## Homebrew での更新

```bash
brew update
brew upgrade --cask mornstorage
```

アプリ内の「更新を確認」からも更新できます。

## Homebrew でのアンインストール

```bash
brew uninstall --cask mornstorage
```

## 使い方

1. 「フォルダを選択」でスキャンする場所を選びます。
2. 面積がサイズに比例した矩形で表示されます。茶色がフォルダ、青がファイルです。
3. 矩形にカーソルを合わせると下部にパスとサイズが出ます。クリックでそのフォルダへ潜り、上部のパンくずで戻ります。
4. 右クリック →「Finderで表示」で該当項目を Finder で開きます。
5. ウィンドウを閉じるとアプリごと終了します。

環境変数 `MORNSTORAGE_PATH` にパスを入れて起動すると、そのフォルダを即座にスキャンします。

```bash
open -a MornStorage --env MORNSTORAGE_PATH="$HOME"
```

## 開発

```bash
swift test
zsh build.sh   # dist/MornStorage.app
```

## ライセンス

[The Unlicense](LICENSE)
