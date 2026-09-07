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

1. 「ボリュームを選択」でスキャンするディスクを選びます。スキャン中も見つかった順に描画されます。
   次回起動時は同じディスクを自動で開き、前回の結果を即座に表示しながら裏で再スキャンし、完了時に差し替えます (`~/Library/Application Support/MornStorage/`)。
2. 面積がサイズに比例したタイルで表示されます。枠線だけのものがフォルダ、色付きタイルがファイルで、色は拡張子ごとに決まります。
3. 右上の ⊟ ⊞ で階層の深さを増減できます。フォルダをクリックして選択中ならそのフォルダ配下だけ、何もない所をクリックして選択を外していれば見えているフォルダ全体が対象です。
4. 矩形にカーソルを合わせると下部にパスとサイズが出ます。フォルダをクリックすると選択され、中身が開閉します。
5. 右クリックメニュー: 詳細表示 (そのフォルダを 1 階層深く) / 簡易表示 (1 階層浅く) / 注目表示 (そのフォルダを親にして表示、パンくずで戻る) / Finderで表示 / 削除 (確認後にゴミ箱へ移動。スキャン中は無効)。
6. ウィンドウを閉じるとアプリごと終了します。

環境変数 `MORNSTORAGE_PATH` にパスを入れて起動すると、そのパスを即座にスキャンします。

```bash
open -a MornStorage --env MORNSTORAGE_PATH="$HOME"
```

## アクセス権について

- 初回スキャンで「写真」「デスクトップ」などへのアクセス許可ダイアログが出ます。ダイアログが出ている間はその領域の走査が止まるので、応答するまで進捗が伸びません。
- 全ディスクを一度で読ませるには、システム設定 →「プライバシーとセキュリティ」→「フルディスクアクセス」に MornStorage を追加してください。以後ダイアログは出ません。
- 許可は署名の同一性で記憶されます。`build.sh` は手元に Developer ID 証明書があればそれで署名するので、ビルドし直しても許可は保持されます。証明書が無い環境ではアドホック署名になり、ビルドのたびに再度求められます。

## 開発

```bash
swift test
MORNSTORAGE_BENCH="$HOME/Library" swift test --filter ScannerBench   # 走査速度の計測
zsh build.sh   # dist/MornStorage.app
```

## ライセンス

[The Unlicense](LICENSE)
