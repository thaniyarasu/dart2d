abstract class JsCallbacksWrapper {
  void bindOnFunction(var jsObject, String methodName, dynamic callback);
  void callJsMethod(var jsObject, String methodName);
  dynamic connectToPeer(var jsPeer, String id);
}
