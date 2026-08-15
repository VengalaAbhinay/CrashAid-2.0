import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'otp_screen.dart';
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() =>
      _PhoneLoginScreenState();
}

class _PhoneLoginScreenState
    extends State<PhoneLoginScreen> {

  final TextEditingController phoneController =
      TextEditingController();

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.black,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),

          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [

              const SizedBox(height: 50),

              const Text(
                "Phone Login",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                "Enter your mobile number",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 40),

              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,

                style: const TextStyle(
                  color: Colors.white,
                ),

                decoration: InputDecoration(
                  hintText: "+91 9876543210",

                  hintStyle: const TextStyle(
                    color: Colors.white38,
                  ),

                  filled: true,
                  fillColor: Colors.white10,

                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,

                height: 55,

                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(16),
                    ),
                  ),

                 onPressed: () async {

  await AuthService().verifyPhoneNumber(

    phoneNumber:
        phoneController.text.trim(),

    codeSent: (verificationId) {

      Navigator.push(
        context,

        MaterialPageRoute(
          builder: (_) => OtpScreen(
            verificationId: verificationId,
          ),
        ),
      );
    },
  );
},
                  child: const Text(
                    "Send OTP",
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}