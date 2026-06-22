import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        'assets/icons/google_logo.svg',
        width: size,
        height: size,
      ),
    );
  }
}
