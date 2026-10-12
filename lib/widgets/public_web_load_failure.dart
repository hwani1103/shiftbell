import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../l10n/l10n_extensions.dart';

/// Keep the failure kind across async work, never a string in an old locale.
enum PublicWebLoadFailure { missingCode, unavailable, unknown }

class PublicWebLoadFailurePage extends StatelessWidget {
  const PublicWebLoadFailurePage({super.key, required this.failure});
  final PublicWebLoadFailure failure;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final reason = switch (failure) {
      PublicWebLoadFailure.missingCode => l.friendLinkMissingCode,
      PublicWebLoadFailure.unavailable => l.friendLoadFailedDetailed,
      PublicWebLoadFailure.unknown => l.friendUnknownError,
    };
    return Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_off, size: 48.sp, color: Colors.grey),
              SizedBox(height: 16.h),
              Text(l.friendCouldNotLoad,
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 8.h),
              Text(reason,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}
