# 장작일기

관심사를 작은 불로 표현하고, 오늘의 활동과 마음을 장작처럼 쌓는 Flutter 앱입니다.

[Figma 홈 화면](https://www.figma.com/design/E4G6JJEdjnJrWhTQ4AaY6E/?node-id=3043-193)을 기준으로 구현했습니다.

## 현재 동작

- 책 읽기, 기타 치기, 달리기 사이를 좌우로 넘길 수 있습니다.
- 상단 + 버튼 또는 캐러셀 끝의 빈 벽난로에서 새 관심사를 만듭니다.
- ‘장작 넣기’에서 현재 관심사의 기록을 작성합니다.
- ‘기록 보기’에서 해당 관심사의 기록을 최신순으로 읽습니다.
- 관심사와 기록은 현재 기기 또는 브라우저의 로컬 저장소에 보관됩니다.
- 저장 실패 시 입력창에 초안을 유지하며 다시 저장할 수 있습니다.

## 실행

```sh
flutter pub get
flutter run
```

## 확인

```sh
flutter analyze
flutter test
flutter build web
```

## 구성

- `lib/home/`: 홈, 캐러셀, 입력 및 기록 시트
- `lib/diary/diary_store.dart`: 기록 모델과 로컬 저장
- `lib/theme/diary_theme.dart`: Figma 색상과 글꼴
- `assets/figma/`: Figma 원본 SVG와 벽난로 렌더링 이미지
- `assets/fonts/`: Noto Sans KR, Noto Serif KR 및 OFL 라이선스

벽난로 PNG는 원본 SVG를 변경하지 않고 3배 크기로 렌더링했습니다. Flutter SVG 렌더러가 지원하지 않는 흐린 그림자 필터를 유지하기 위한 파일입니다. 아이콘과 공간의 빛은 원본 SVG로 표시하며, 실행 중 임시 Figma URL을 사용하지 않습니다.

상태 표시줄과 홈 인디케이터는 운영체제가 표시합니다. 제공되지 않은 입력·조회 화면은 홈의 색상과 글꼴을 이어받는 시트로 구성했습니다. 서버 연결과 계정 간 동기화는 포함하지 않습니다.
