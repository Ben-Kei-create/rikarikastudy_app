# ドパリカ!

問題で世界をうごかす理科クイズ iOS アプリ (Swift / SwiftUI / SwiftData)。
元ネタ: [rikarikastudy](https://github.com/Ben-Kei-create/rikarikastudy)

## 構成
- `doparika/Models` — Question (JSON) / SwiftData モデル
- `doparika/Services` — QuizEngine, QuestionSelector(復習ミックス), LevelCalculator, WorldMotionController, CollectionService ほか
- `doparika/Views` — Home / Quiz / Result / Collection、画像優先・コード描画フォールバックの地層背景 (`WorldBackgroundView`)
- `doparika/Resources/questions_mountain.json` — 山ステージ問題 (ID は一度発行したら不変)
- `tools/build_questions.py` — rikarikastudy の choice4 問題を 2 択に変換 (既存ファイルがあると再生成を拒否)

## 対応端末・Bundle ID

- **iPhone専用・縦画面のみ**（`TARGETED_DEVICE_FAMILY = 1`、横画面・iPad は非対応）。
- Bundle ID は `com.fumiakimogi.doparika`。開発初期の `devplaceholder.*.doparika` から変更したため、旧ビルドの保存データ（XP・解放履歴）は引き継がれない。開発用データなので移行はしない（リリース前の仕様）。

## 初回リリース仕様
Lv.1〜30 / 山・地層 / 2択 / 1セッション5問 / 制限時間15秒 / 正解 +20XP

## 背景Assetの差し替え

- `home_bg`、`section_01`〜`section_10`、`AppIcon` の名前を維持する。
- 山の素材は縦横比約1:3（現在724×2172px、本番は1206×3000px程度でも可）。**1セクションの高さは画面幅の3倍**（`WorldMotionController.sectionAspect`）で、画像の上下端はクロップされず継ぎ目が保たれる。左右は中央基準のAspect Fillで、極端な縦横比の画像では左右がクロップされる。
- Asset内の画像だけを交換すればよく、Swiftコードやセクション位置の変更は不要。解像度やAssetのscale指定が変わってもセクションの高さは変わらない。
- 画面に交差するセクションだけを描画する。隣接セクションは高さの12%（`overlapFraction`）だけ重ね、重なり部分を smoothstep でクロスフェードして継ぎ目を見せない。重なり部分では二つの絵が溶け合うため、境界付近の化石などが薄く二重に見えることがある（素材側で境界付近を無地寄りにすると改善）。
- `home_bg` が欠けた場合は地層背景へ、各 `section_XX` が欠けた場合はその区間だけコード描画へ戻る。
- ロゴ、羊皮紙、正誤・満点演出、空・海ティザーの追加素材は未導入。

## 問題データ

- `tools/build_questions.py` — 初回生成（既存ファイルがあると拒否）。
- `tools/fetch_supabase.py` — rikarikastudy の Supabase から2択化できる問題を **追記のみ** で取り込む（既存IDは不変、`--dry-run` あり）。`.env` に `SUPABASE_URL` / `SUPABASE_KEY`（Publishable key）を置く。`.env` はコミットしない。
- 現在 874 問（`00001`〜`00874`）。

## 検証

### 自動テスト（XCTest）

```sh
xcodebuild -project doparika.xcodeproj -scheme doparika -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

`doparikaTests`: 背景モーション（境界・回転・ドリフト上限）、回答期限・一時停止・問題切替の時計、再挑戦の位置継承、保存（XP・解放・誤答）、出題（5問・復習混合）、問題データ。

### 背景レイアウトの独立チェック

```sh
xcrun swiftc -parse-as-library doparika/Services/WorldMotionController.swift doparika/Views/WorldSectionLayout.swift tools/check_background_layout.swift -o /tmp/doparika-background-checks
/tmp/doparika-background-checks
```

画面確認の結果と未確認事項は `docs/qa/asset-readiness.md` を参照。
