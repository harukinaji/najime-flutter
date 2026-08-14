import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PhoneVerificationService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _verificationId;
  int? _resendToken;

  Future<void> sendCode({
    required String phoneNumber,
    required void Function(String error) onError,
    required void Function() onCodeSent,
    required void Function(PhoneAuthCredential credential) onAutoVerify,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) {
          onAutoVerify(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('Phone verification failed: ${e.code} - ${e.message}');
          onError(_friendlyError(e));
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          onCodeSent();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      debugPrint('Phone verification exception: $e');
      onError(_handleGenericError(e));
    }
  }

  Future<bool> verifyCode({
    required String smsCode,
    required void Function(String error) onError,
    required void Function(String phoneNumber) onSuccess,
  }) async {
    if (_verificationId == null) {
      onError('No verification in progress. Request a new code.');
      return false;
    }

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      final phone = userCredential.user?.phoneNumber;
      if (phone != null) {
        onSuccess(phone);
        return true;
      }
      onError('Verification succeeded but phone number is unavailable.');
      return false;
    } on FirebaseAuthException catch (e) {
      onError(_friendlyError(e));
      return false;
    } catch (e) {
      onError(_handleGenericError(e));
      return false;
    }
  }

  Future<void> linkPhoneNumber({
    required String smsCode,
    required void Function(String error) onError,
    required void Function(String phoneNumber) onSuccess,
  }) async {
    if (_verificationId == null) {
      onError('No verification in progress. Request a new code.');
      return;
    }

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      final user = _auth.currentUser;
      if (user == null) {
        onError('No authenticated user found.');
        return;
      }
      await user.linkWithCredential(credential);
      onSuccess(user.phoneNumber ?? '');
    } on FirebaseAuthException catch (e) {
      onError(_friendlyError(e));
    } catch (e) {
      onError(_handleGenericError(e));
    }
  }

  String _handleGenericError(Object e) {
    final msg = e.toString();
    if (msg.contains('CONFIGURATION_NOT_FOUND') || msg.contains('17499')) {
      return 'Phone verification is not available. '
          'Please contact support or try again later.';
    }
    if (msg.contains('ADMIN_ONLY_OPERATION') || msg.contains('10000')) {
      return 'Phone authentication is not enabled for this project.';
    }
    return 'An unexpected error occurred. Please try again.';
  }

  String _friendlyError(FirebaseAuthException e) {
    debugPrint('FirebaseAuth error: code=${e.code}, message=${e.message}');

    switch (e.code) {
      case 'invalid-phone-number':
        return 'The phone number is invalid.';
      case 'too-many-requests':
        return 'Too many requests. Please try again later.';
      case 'invalid-verification-code':
      case 'invalid-verification-id':
        return 'The verification code is incorrect.';
      case 'session-expired':
        return 'The verification session has expired. Request a new code.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';
      case 'credential-already-in-use':
        return 'This phone number is already linked to another account.';
      case 'requires-recent-login':
        return 'Please sign in again to change your phone number.';
      case 'configuration-not-found':
      case 'auth/ configuration-not-found':
        return 'Phone verification is not configured. '
            'Please contact support.';
      default:
        if (e.message != null && e.message!.contains('CONFIGURATION_NOT_FOUND')) {
          return 'Phone verification is not available. '
              'Please contact support or try again later.';
        }
        return e.message ?? 'An error occurred during phone verification.';
    }
  }
}
