# Stakeholder demo guide

Live demo: <https://rmranjit.github.io/FlutterTFlow/>

A 5-minute walkthrough for a non-technical audience. Goal: they *see* the camera understanding movement, and leave
knowing what it could mean for the product.

## Before the meeting (10 min)

- [ ] Use **Chrome or Edge** (desktop), or Safari on iPad. Open the hosted link, or `flutter run -d chrome`.
- [ ] Camera needs **https or localhost**. A file opened from disk will not work.
- [ ] Do a full dry run **on the same machine and network** you'll present from. First load downloads ~20 MB of models.
- [ ] Face a window or lamp (light on your face, not behind you). Plain background helps.
- [ ] Sit or stand far enough back that **head and shoulders are fully visible**; for the "Jump" step, the whole body.
- [ ] Close other camera apps (Zoom/Teams hold the camera). If you screen-share via Zoom, share the browser **tab**.
- [ ] Have a backup: a 60-second screen recording of a good run.

## Script

1. **Set the scene (30 s).** "This uses an ordinary camera and AI running *in the browser*. No video is recorded or sent anywhere."
   Click **Start camera**, allow access. Point to the skeleton: "It finds the joints of my body and face in real time."
2. **Show live understanding (60 s).** Raise a hand, then lean, then smile. Read the *Right now* card aloud as it changes.
   "It isn't just drawing dots, it's concluding things: *hand raised, leaning, smiling*."
3. **Hand over the challenge (90 s).** Invite a stakeholder to try the **Try these** checklist. Items tick off as the camera
   recognises them. **Rehearse first and note which ones work reliably for you**: gestures are rule-based and were only
   tested on synthetic data and still photos, so expect some (e.g. *Cross your arms*, *Jump*) to be hit-and-miss.
   If one won't tick, move on; don't force it in front of the room.
4. **Show the "so what" (60 s).** Tap **Calibrate posture** sitting upright, then slouch for ~10 s: a *Posture check* alert appears.
   Stay still for a minute and it suggests a stretch. "This is the kind of wellbeing insight we could build on."
5. **Close (30 s).** Mention it runs on phone and tablet too (show on a phone/iPad if you have one). Ask for use-cases.

Presenter tip: the **chart icon** (top right) shows technical details (model, frame rate). Keep it off unless asked.

## Likely questions

| Question | Honest answer |
|---|---|
| Is video stored or sent anywhere? | No. Processing happens on the device. (Only the AI models are downloaded from the internet at start-up.) |
| How accurate is it? | Good for large, clear movements with one person facing the camera. It is a proof of concept: gestures are rule-based and can miss or misfire with poor light or hidden arms. |
| Does it work on phones? | The same app builds for Android/iOS. The web version is the one tested end to end; mobile still needs device testing. |
| What can't it do yet? | Several people at once, subtle emotions, and on mobile the face expressions (smile, etc.). |
| What would it take to productionise? | Device testing and tuning, a face model on mobile, accuracy measurement with real users, accessibility and privacy review. |

## If something goes wrong

- *"Camera permission was denied"*: click the camera icon in the address bar, allow, then **Try again**.
- *"No person in view"*: step back; make sure your shoulders are visible.
- *Choppy / slow*: close other tabs and heavy apps; plug in the laptop. Software-only graphics can drop to a few frames per second.
- *Nothing loads*: needs internet on first load (models come from a CDN). Switch network or fall back to the recording.
