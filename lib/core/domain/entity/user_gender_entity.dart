import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:opennutritracker/core/data/dbo/user_gender_dbo.dart';
import 'package:opennutritracker/generated/l10n.dart';

enum UserGenderEntity {
  male,
  female,
  nonBinary;

  static const Color maleColor = Color(0xFF5BCEFA);
  static const Color femaleColor = Color(0xFFF5A9B8);
  static const Color nonBinaryColor = Color(0xFF9C59D1);
  static const String nonBinaryIconAsset = 'assets/icon/nonbinary_symbol.svg';

  factory UserGenderEntity.fromUserGenderDBO(UserGenderDBO genderDBO) {
    switch (genderDBO) {
      case UserGenderDBO.male:
        return UserGenderEntity.male;
      case UserGenderDBO.female:
        return UserGenderEntity.female;
      case UserGenderDBO.nonBinary:
        return UserGenderEntity.nonBinary;
    }
  }

  String getName(BuildContext context) {
    switch (this) {
      case UserGenderEntity.male:
        return S.of(context).genderMaleLabel;
      case UserGenderEntity.female:
        return S.of(context).genderFemaleLabel;
      case UserGenderEntity.nonBinary:
        return S.of(context).genderNonBinaryLabel;
    }
  }

  Color getColor() {
    switch (this) {
      case UserGenderEntity.male:
        return maleColor;
      case UserGenderEntity.female:
        return femaleColor;
      case UserGenderEntity.nonBinary:
        return nonBinaryColor;
    }
  }

  Widget getIcon({double size = 24, Color? color}) {
    switch (this) {
      case UserGenderEntity.male:
        return Icon(Icons.male_outlined, size: size, color: color ?? maleColor);
      case UserGenderEntity.female:
        return Icon(
          Icons.female_outlined,
          size: size,
          color: color ?? femaleColor,
        );
      case UserGenderEntity.nonBinary:
        return SvgPicture.asset(
          nonBinaryIconAsset,
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(
            color ?? nonBinaryColor,
            BlendMode.srcIn,
          ),
        );
    }
  }
}
