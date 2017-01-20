library fps_counter;

import 'package:di/di.dart';

@Injectable()
class FpsCounter extends _FrameTrigger {
  FpsCounter() : super(1.0);
}

class _FrameTrigger {
  double _period = 1.0;
  double _fps = 0.0;

  double _nextTriggerIn = 1.0;
  int frames = 0;

  _FrameTrigger(double period) {
    this._period = period;
    this._nextTriggerIn = period;
  }

  bool timeWithFrames(double time, int framesPassed) {
    this.frames += framesPassed;
    _nextTriggerIn -= time;
    if (_nextTriggerIn < 0.0) {
      _fps = frames / (1.0 - _nextTriggerIn);
      frames = 0;
      _nextTriggerIn += _period;
      return true;
    }
    return false;
  }
  
  String toString() {
    return _fps.toStringAsFixed(2);
  }

  double fps() => _fps;
}
