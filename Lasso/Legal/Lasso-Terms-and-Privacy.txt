# Lasso — Terms of Use and Privacy

Last updated: November 9, 2026

Lasso is a free Mac app that organizes your photos and videos on your own computer. These terms explain how you can use it and what happens to your information.

## The short version

- **Your files stay yours, on your Mac.** Lasso has no accounts, no servers, no analytics and no ads. The developer of Lasso never receives your files or any information about them.
- **Lasso never permanently deletes anything.** In Move mode, originals go to your Mac's Trash only after their copy has been checked.
- **Two things can use the internet:** a one-time download of the transcription add-on, and Apple's place-name lookup for photos and videos that contain a GPS location.
- **Face mapping is off unless you turn it on.** Faceprints and names stay on your Mac and are never put into file names or Finder tags. You can delete them at any time.
- **Lasso is free and provided as is,** without any warranty. Keep a backup of anything important.

## Terms of Use

**Using Lasso.** Lasso is free to download and use. By installing or using it, you agree to these terms. If you don't agree, please don't use Lasso.

**Open source.** Lasso's source code is published on GitHub under the MIT License. You may use, copy, change and share it under that licence, which is included with the download.

**Provided as is.** Lasso is offered as is, without warranty of any kind. Its developer is not liable for any loss of files, data or time arising from its use, to the extent the law allows. Footage-type suggestions, transcripts, place names and face matches are made automatically and can be wrong, so please check them.

**Your files.** You choose which folders Lasso reads and what it does to them. Lasso copies, moves or renames files only when you confirm. It never permanently deletes them: in Move mode the original goes to your Mac's Trash after its copy has been checked, and you can restore it from there until you empty the Trash. Keep a backup of anything you can't afford to lose.

**Other people in your files.** If you use face mapping, you may be identifying people other than yourself. Please respect their privacy, and only name people you have a good reason to name.

**Third-party parts.** Lasso includes open-source components with their own licences: WhisperKit by Argmax (MIT), SFace from the OpenCV Zoo (Apache 2.0), ONNX Runtime by Microsoft (MIT), the Opus Motion Library (MIT), and the Fraunces, Inter, Sacramento and JetBrains Mono fonts (SIL Open Font License). Their licence texts are included with the download.

**Changes.** These terms may be updated with new versions of Lasso. The date at the top shows when they last changed, and the latest version is always on Lasso's GitHub page.

**Governing law.** These terms are governed by the laws of France, without affecting any rights you have under the laws of the country where you live.

## Privacy

Lasso does all of its work on your Mac. Its developer doesn't collect, receive, store or sell any information about you or your files.

### What Lasso keeps on your Mac

| What | Where | How to remove it |
| --- | --- | --- |
| Your settings and source folder list | Lasso's app preferences | Delete Lasso with "Remove Lasso's catalog…" ticked |
| Rename log (old and new file names) | Your library folder, in a hidden .lasso folder | Turn off "Keep a log" or delete that folder |
| Transcripts (.srt files) | Next to each transcribed clip | Delete the .srt file, or move the clip to the Trash from the Library |
| Transcription add-on (about 0.5 GB) | ~/Library/Application Support/Lasso/Models | Delete Lasso with "Remove Lasso's catalog…" ticked |
| Face mapping data: faceprints, names, small face pictures | ~/Library/Application Support/Lasso/Faces | Settings › People › Delete All Face Mapping Data |
| Finder tags (footage type and place) | On each wrangled file | Turn off "Write tags…" before wrangling, or remove the tags in Finder |

### When Lasso uses the internet

- **Transcription add-on:** if you turn on transcription, Lasso downloads the Whisper model once from Hugging Face, through WhisperKit by Argmax. After that, transcription runs entirely on your Mac and no audio leaves it.
- **Place names:** when a photo or video contains a GPS location, Lasso asks Apple's location service for the name of the city. Only the coordinates are sent, never the file, and Apple's own privacy policy applies to that request.

Lasso makes no other internet connections.

### Face mapping

Face mapping is off until you turn it on. When it's on, Lasso detects faces with Apple's built-in Vision framework and turns each one into a faceprint, a list of numbers that describes the face. That work happens on your Mac, and faceprints never leave it.

- Faceprints count as biometric data under privacy laws such as the EU's GDPR. Lasso keeps them only on your Mac, under your control, and uses them only to group your files by person.
- Names you give are linked to files inside Lasso only. They're never put into file names or Finder tags, and they don't appear in Finder or Spotlight searches.
- When you choose not to track someone, Lasso keeps one unnamed faceprint as a marker so it doesn't ask about them again. It keeps no name and no picture of them.
- You can remove one person in Settings › People, or everything with Delete All Face Mapping Data.

### Deleting everything

In Settings, choose Delete Lasso and tick "Remove Lasso's catalog, thumbnails and AI models". This removes the app and everything listed above except your transcripts and Finder tags, which stay with your files. Your photos and videos are never deleted.

### Children

Lasso isn't designed for children and doesn't knowingly process information about anyone in particular. It only works with the files you choose.

### Questions

If you have a question about these terms or about privacy, open an issue on Lasso's GitHub page.
