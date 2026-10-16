# ドパリカ!

問題で世界をうごかす理科クイズ iOS アプリ (Swift / SwiftUI / SwiftData)。
元ネタ: [rikarikastudy](https://github.com/Ben-Kei-create/rikarikastudy)

## 構成
- `doparika/Models` — Question (JSON) / SwiftData モデル
- `doparika/Services` — QuizEngine, QuestionSelector(復習ミックス), LevelCalculator, WorldMotionController, CollectionService ほか
- `doparika/Views` — Home / Quiz / Result / Collection、画像優先・コード描画フォールバックの地層背景 (`WorldBackgroundView`)
- `doparika/Resources/questions_mountain.json` — 山ステージ問題 (ID は一度発行したら不変)
- `tools/build_questions.py` — rikarikastudy の choice4 問題を 2 択に変換 (既存ファイルがあると再生成を拒否)

## 初回リリース仕様
Lv.1〜30 / 山・地層 / 2択 / 1セッション5問 / 制限時間15秒 / 正解 +20XP

## 背景Assetの差し替え

- `home_bg`、`section_01`〜`section_10`、`AppIcon` の名前を維持する。
- 山の本番素材は約1206×3000pxを想定。各セクションは画像サイズと独立した1000ptの領域に、縦横比を保った中央基準のAspect Fillで描画する。画面幅によって端がクロップされるため、重要な絵柄は中央寄りに配置する。
- Asset内の画像だけを交換すればよく、Swiftコードやセクション位置の変更は不要。画像の解像度やAssetのscale指定が変わってもセクションの高さは変わらない。
- 画面に交差するセクションだけを描画し、各画像をセクション領域でクリップする。隣接セクションは同じピクセル境界を共有し、隙間や画像寸法による位置ずれを防ぐ。画像間の色の連続性は素材側で調整する。
- `home_bg` が欠けた場合は地層背景へ、各 `section_XX` が欠けた場合はその区間だけ従来のコード描画へ戻る。画像が存在する区間では画像を優先する。
- ロゴ、羊皮紙、正誤・満点演出、空・海ティザーの追加素材は未導入。

## 背景レイアウトの検証

現時点でXcodeのテストターゲットはない。以下は本番の座標計算を使い、仮の603×603px、本番想定1206×3000px、横長画像について、全セクションの接続・画像の被覆・縦横比を検証する独立チェック。

```sh
xcrun swiftc -parse-as-library doparika/Services/WorldMotionController.swift doparika/Views/WorldSectionLayout.swift tools/check_background_layout.swift -o /tmp/doparika-background-checks
/tmp/doparika-background-checks
```

Simulatorでの確認結果と検証範囲は `docs/qa/asset-readiness.md` を参照。
