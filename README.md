# Movement Insights — Flutter + TensorFlow Lite proof of concept

Detects **face and body movement** from the camera with TensorFlow Lite models, turns the raw landmarks
into **inferences** (posture, gestures, motion, expression, wellbeing alerts) and shows them live.
Runs on **web, phone and tablet** from one Flutter codebase. All inference is on-device; no video is uploaded.

## What it infers

| Group | Examples |
|---|---|
| Posture | standing / sitting / squatting / lunging, leaning left/right, head tilt, slouching (after calibration) |
| Gestures | left / right / both hands raised, arms crossed, wave, head nod, head shake, jump |
| Face (web) | smiling, surprised, mouth open, brows raised, blinks per minute, looking away |
| Motion | still / light / active, with a 0–100 % activity meter |
| Wellbeing | "time to stretch" after prolonged stillness, posture-check after sustained slouching, drowsiness (eyes closed) |

## Architecture

```
camera ─▶ MotionDetector (platform specific) ─▶ DetectionFrame ─▶ MovementAnalyzer ─▶ UI
           web:    MediaPipe Tasks (pose + face landmarker, TFLite in WASM/WebGL)
           mobile: tflite_flutter + MoveNet Lightning (17 keypoints)
```

* `lib/models` – shared landmark types. Both backends emit the MediaPipe 33-point body layout
  (MoveNet's 17 points fill the subset used for analysis).
* `lib/detection` – the `MotionDetector` interface and one implementation per platform, selected with
  conditional imports so web builds never pull in `dart:ffi` and mobile builds never pull in `dart:js_interop`.
  `frame_preprocessor.dart` (YUV/BGRA → rotated, letterboxed RGB) is plugin-free and unit-tested.
* `lib/analysis` – `MovementAnalyzer`: pure Dart, no platform dependencies, driven by timestamps (frame-rate
  independent), distances measured in shoulder-widths (camera-distance independent).
* `lib/ui` – responsive shell: side by side on wide/landscape screens (desktop web, tablets, landscape phones),
  stacked on portrait phones/tablets.

**Why two backends?** `tflite_flutter` does not support web. MediaPipe Tasks runs TFLite models in the browser
(WASM), is what Google recommends for web, and additionally provides 52 face blendshapes. On mobile we run a
`.tflite` model directly through `tflite_flutter`.

## Run it

```bash
flutter pub get
flutter run -d chrome          # web (camera needs https or localhost)
flutter run -d <device-id>     # Android (API 26+) or iOS (physical device recommended)
flutter test                   # unit + widget tests
```

Web loads the MediaPipe runtime from jsDelivr and the pose/face models from `storage.googleapis.com` on first
start (~20 MB, cached by the browser). To make it work offline, download them into `web/` and change the URLs at the
top of `web/motion_bridge.js`.

## Tested vs. not tested

Verified in this repo: analysis logic (synthetic poses), mobile frame preprocessing (rotations, letterbox, YUV),
head-pose maths, responsive layout (phone / tablet / desktop sizes), and the **web pipeline end to end** in headless
Chromium with a fake camera fed real photos (models load, camera opens, skeleton, face outline and inferences render).

**Not yet run on a real Android/iOS device.** The mobile backend compiles and analyses clean, and its image
handling is unit-tested, but camera rotation/mirroring and MoveNet accuracy still need a device pass.

## Known limitations (POC)

* Mobile has no face-expression data (MoveNet is body-only). Add a face model (e.g. BlazeFace + FaceMesh or
  `google_mlkit_face_detection`) behind the same `FaceFrame` type to close this gap.
* Mobile inference runs on the UI isolate; move it to a background isolate for production.
* Single person only. "Slouching" needs one tap on **Calibrate posture**.
* Gesture rules are heuristics, tuned on synthetic data; they degrade with occluded or cropped limbs
  (e.g. arms-crossed is unreliable in a waist-up crop). Thresholds live in `AnalyzerConfig`.
* Frame rate on web depends on the GPU; software rendering gives only a few fps.
