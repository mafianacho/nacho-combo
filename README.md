# Nacho Combo (MVP)

하나의 macOS 앱에서 세 모듈을 각각 ON/OFF 한다. 타사 앱·코드·브랜드를 사용하지 않는다.

| 모듈 | 내용 | 권한 |
|---|---|---|
| 메뉴 막대 정리 | 구분선 왼쪽 아이콘 접기/펼치기 ([제약](docs/MENUBAR-CONSTRAINTS.md)) | 없음 |
| 시스템 모니터 | CPU·메모리·네트워크 (2초 간격) | 없음 |
| 창 배치 | ⌃⌥← / ⌃⌥→ / ⌃⌥↩ 왼쪽·오른쪽·최대화 | 손쉬운 사용 |

- 대상: macOS 12 (Monterey) 이상, Swift 5.5+ (Package.swift `platforms: .macOS(.v12)`).
- 설정: `~/Library/Application Support/NachoCombo/settings.json` (기본값은 전부 OFF).
- OFF 계약: 모듈 `stop()`이 타이머·핫키·상태 아이템을 모두 해제한다. `state.json`(같은 폴더)에 확인용 카운터가 기록된다.
- 권한 거부: 창 배치를 켰는데 권한이 없으면 아무것도 등록하지 않고 안내(설정 열기 버튼, 재확인)를 표시한다. 우회하지 않는다.

## 설치 (릴리즈)
- [Releases](../../releases)에서 `NachoCombo-<버전>-macos.zip` 또는 `.dmg`와 `SHA256SUMS.txt`를 받는다. 유니버설 바이너리(Apple Silicon + Intel), macOS 12 이상.
- 검증: `shasum -a 256 -c SHA256SUMS.txt`
- **서명 한계: ad-hoc 서명이며 Apple Developer ID 서명·공증(notarization)이 없다.** 처음 실행하면 Gatekeeper가 막는다.
  앱을 우클릭 → 열기 → 열기, 또는 시스템 설정 ▸ 개인정보 보호 및 보안에서 허용한다. 업데이트·재빌드하면 코드 서명이 바뀌므로
  창 배치의 손쉬운 사용 권한을 다시 허용해야 한다.
- 릴리즈는 `v0.1.0` 형식 태그를 푸시하면 GitHub Actions(`.github/workflows/release.yml`)가 macOS 러너에서 빌드·패키징해 자동 생성한다.

## 빌드 / 시험
- macOS: `scripts/build-app.sh` → `build/NachoCombo.app` (ad-hoc 서명). 실행 `open build/NachoCombo.app`.
  유니버설 빌드 `UNIVERSAL=1`, 버전 지정 `VERSION=x.y.z`, 패키징 `VERSION=x.y.z scripts/package.sh` (zip·dmg·SHA256SUMS → `dist/`).
- Core 단위시험(Linux/macOS 공통): `swift test` (Linux에서는 AppKit 타깃이 매니페스트에서 제외됨).
- 디버그 제어 채널: `NachoCombo --debug-ctl`로 실행 후 `NachoCombo ctl set systemMonitor off|on`, `ctl collapse on|off`,
  `ctl snap left|right|maximize`, `ctl dump`, `ctl quit`. 상태 JSON을 출력한다. 릴리스 사용 대상 아님.

## 라이선스
[MIT](LICENSE) © 2026 Mafianacho (마피아나초). "Nacho Combo" 이름과 로고는 이 라이선스의 허락 대상이 아니다.
