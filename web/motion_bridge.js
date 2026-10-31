// Bridge between Flutter web and MediaPipe Tasks Vision. MediaPipe executes
// TensorFlow Lite models (pose + face landmarkers) in WebAssembly, which is the
// supported way to run TFLite in a browser; `tflite_flutter` has no web support.
//
// Dart calls: init(), startCamera(video), stopCamera(video), detect(video, ts).
// detect() returns a JSON string (or null) to keep the interop surface tiny.

const VERSION = '0.10.14';
const CDN = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${VERSION}`;
const MODELS = 'https://storage.googleapis.com/mediapipe-models';
const POSE_MODEL = `${MODELS}/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task`;
const FACE_MODEL = `${MODELS}/face_landmarker/face_landmarker/float16/latest/face_landmarker.task`;

// MediaPipe FACEMESH_FACE_OVAL, in drawing order.
const FACE_OVAL = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109];

let pose = null;
let face = null;
let initPromise = null;
let lastTs = 0;

async function doInit() {
  const { FilesetResolver, PoseLandmarker, FaceLandmarker } = await import(`${CDN}/vision_bundle.mjs`);
  const vision = await FilesetResolver.forVisionTasks(`${CDN}/wasm`);

  const build = async (Cls, modelPath, extra) => {
    const opts = (delegate) => ({
      baseOptions: { modelAssetPath: modelPath, delegate },
      runningMode: 'VIDEO',
      ...extra,
    });
    try {
      return await Cls.createFromOptions(vision, opts('GPU'));
    } catch (e) {
      console.warn('GPU delegate unavailable, falling back to CPU', e);
      return await Cls.createFromOptions(vision, opts('CPU'));
    }
  };

  pose = await build(PoseLandmarker, POSE_MODEL, { numPoses: 1 });
  face = await build(FaceLandmarker, FACE_MODEL, {
    numFaces: 1,
    outputFaceBlendshapes: true,
    outputFacialTransformationMatrixes: true,
  });
}

window.motionBridge = {
  init() {
    initPromise ??= doInit().catch((e) => {
      initPromise = null;
      throw new Error(`Could not load the TFLite models: ${e && e.message ? e.message : e}`);
    });
    return initPromise;
  },

  async startCamera(video) {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      throw new Error('Camera access needs a secure (https or localhost) context.');
    }
    let stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } },
        audio: false,
      });
    } catch (e) {
      const name = e && e.name;
      if (name === 'NotAllowedError' || name === 'SecurityError') throw new Error('Camera permission was denied.');
      if (name === 'NotFoundError' || name === 'OverconstrainedError') throw new Error('No camera was found on this device.');
      throw new Error(`Could not open the camera: ${e && e.message ? e.message : e}`);
    }
    video.srcObject = stream;
    await video.play();
  },

  stopCamera(video) {
    const s = video.srcObject;
    if (s) s.getTracks().forEach((t) => t.stop());
    video.srcObject = null;
  },

  detect(video, ts) {
    if (!pose || !face || video.readyState < 2 || !video.videoWidth) return null;
    ts = Math.max(ts, lastTs + 1);
    lastTs = ts;

    const p = pose.detectForVideo(video, ts);
    const f = face.detectForVideo(video, ts);

    const out = { w: video.videoWidth, h: video.videoHeight };
    const body = p.landmarks && p.landmarks[0];
    if (body) out.pose = body.map((l) => [l.x, l.y, l.z, l.visibility ?? 1]);

    const lm = f.faceLandmarks && f.faceLandmarks[0];
    if (lm) {
      const blend = {};
      const cats = f.faceBlendshapes && f.faceBlendshapes[0] && f.faceBlendshapes[0].categories;
      if (cats) for (const c of cats) blend[c.categoryName] = c.score;
      const m = f.facialTransformationMatrixes && f.facialTransformationMatrixes[0];
      out.face = {
        blend,
        matrix: m ? Array.from(m.data) : null,
        outline: FACE_OVAL.map((i) => [lm[i].x, lm[i].y]),
      };
    }
    return JSON.stringify(out);
  },
};
