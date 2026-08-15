import 'dart:js_interop';

@JS('_speechTriggerCallback')
external set _speechTriggerCallback(JSFunction? fn);

@JS('startSpeechRecognition')
external void _startSpeechRecognition(JSArray<JSString> keywords);

@JS('stopSpeechRecognition')
external void _stopSpeechRecognition();

void startWebSpeech(Function(String) onTrigger) {
  _speechTriggerCallback = ((JSString transcript) {
    onTrigger(transcript.toDart);
  }).toJS;

  _startSpeechRecognition(
    ['help', 'sos', 'emergency', 'bachao', 'help me']
        .map((k) => k.toJS)
        .toList()
        .toJS,
  );
}

void stopWebSpeech() {
  _stopSpeechRecognition();
}