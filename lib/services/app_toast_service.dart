import 'package:fluttertoast/fluttertoast.dart';

class AppToastService {
  AppToastService._();

  static Future<bool?> show(String message) {
    return Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
    );
  }
}
