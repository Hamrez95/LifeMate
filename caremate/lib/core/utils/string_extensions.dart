import 'package:lifemate_client/lifemate_client.dart';

extension PersianNumberExtension on String {
  String toPersianDigit(bool isPersian) => isPersian
      ? LifeMateNumbers.toPersian(this)
      : LifeMateNumbers.toLatin(this);

  String toLatinDigit() => LifeMateNumbers.toLatin(this);
}
