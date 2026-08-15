import 'package:flutter/material.dart';

class OtpScreen extends StatelessWidget {

  final String verificationId;

  const OtpScreen({
    super.key,
    required this.verificationId,
  });

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.black,

      body: Center(
        child: Text(
          "OTP Verification Screen",
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
          ),
        ),
      ),
    );
  }
}