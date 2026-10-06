import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../users/data/station_grants.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({
    super.key,
    required this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() =>
      _LoginScreenState();
}

class _LoginScreenState
    extends State<LoginScreen> {
  final _emailController =
  TextEditingController();

  final _passwordController =
  TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();

    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await AppServices
          .authRepository
          .login(
        email:
        _emailController.text,
        password:
        _passwordController.text,
      );

      //
      // بعد نجاح Login وحفظ:
      // - Access Token
      // - Refresh Token
      // - Active Branch ID
      //
      // نبدأ خدمة المزامنة.
      //
      // startSync() آمنة للاستدعاء أكثر من مرة
      // لأن SyncService يمنع التشغيل المكرر.
      //
      await AppServices.startSync();

      if (!mounted) {
        return;
      }

      widget.onLoginSuccess();
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message =
      error
          .toString()
          .replaceFirst(
        'Bad state: ',
        '',
      );

      ScaffoldMessenger
          .of(context)
          .showSnackBar(
        SnackBar(
          content:
          Text(
            message,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor:
      AppTheme.backgroundColor,
      body: Center(
        child:
        SingleChildScrollView(
          padding:
          const EdgeInsets.all(
            32,
          ),
          child: Container(
            width: 440,
            padding:
            const EdgeInsets.all(
              34,
            ),
            decoration:
            BoxDecoration(
              color:
              Colors.white,
              borderRadius:
              BorderRadius.circular(
                24,
              ),
              border:
              Border.all(
                color:
                AppTheme
                    .subtleBorderColor,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                  Colors.black
                      .withValues(
                    alpha:
                    0.05,
                  ),
                  blurRadius:
                  40,
                  offset:
                  const Offset(
                    0,
                    14,
                  ),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment
                  .stretch,
              children: [
                Align(
                  alignment:
                  Alignment.center,
                  child:
                  Container(
                    width:
                    58,
                    height:
                    58,
                    decoration:
                    BoxDecoration(
                      color:
                      const Color(
                        0xFF1D1D1F,
                      ),
                      borderRadius:
                      BorderRadius
                          .circular(
                        17,
                      ),
                    ),
                    child:
                    const Icon(
                      Icons
                          .query_stats_rounded,
                      color:
                      Colors.white,
                      size:
                      27,
                    ),
                  ),
                ),

                const SizedBox(
                  height:
                  22,
                ),

                const Text(
                  'نظام المبيعات',
                  textAlign:
                  TextAlign.center,
                  style:
                  TextStyle(
                    fontSize:
                    27,
                    fontWeight:
                    FontWeight.w700,
                    letterSpacing:
                    -0.5,
                    color:
                    AppTheme
                        .primaryTextColor,
                  ),
                ),

                const SizedBox(
                  height:
                  7,
                ),

                const Text(
                  'دخول الحاسبة الأساسية وباقي الحاسبات',
                  textAlign:
                  TextAlign.center,
                  style:
                  TextStyle(
                    fontSize:
                    13,
                    color:
                    AppTheme
                        .secondaryTextColor,
                  ),
                ),

                const SizedBox(
                  height:
                  30,
                ),

                const Text(
                  'اسم الدخول أو البريد',
                  style:
                  TextStyle(
                    fontSize:
                    12,
                    fontWeight:
                    FontWeight.w500,
                    color:
                    AppTheme
                        .primaryTextColor,
                  ),
                ),

                const SizedBox(
                  height:
                  7,
                ),

                TextField(
                  controller:
                  _emailController,
                  enabled:
                  !_isLoading,
                  keyboardType:
                  TextInputType
                      .text,
                  textInputAction:
                  TextInputAction
                      .next,
                  decoration:
                  const InputDecoration(
                    hintText:
                    'example@sayler.app',
                    prefixIcon:
                    Icon(
                      Icons
                          .mail_outline_rounded,
                      size:
                      19,
                    ),
                  ),
                ),

                const SizedBox(
                  height:
                  18,
                ),

                const Text(
                  'كلمة المرور',
                  style:
                  TextStyle(
                    fontSize:
                    12,
                    fontWeight:
                    FontWeight.w500,
                    color:
                    AppTheme
                        .primaryTextColor,
                  ),
                ),

                const SizedBox(
                  height:
                  7,
                ),

                TextField(
                  controller:
                  _passwordController,
                  enabled:
                  !_isLoading,
                  obscureText:
                  _obscurePassword,
                  textInputAction:
                  TextInputAction
                      .done,
                  onSubmitted:
                      (_) =>
                      _login(),
                  decoration:
                  InputDecoration(
                    hintText:
                    'أدخل كلمة المرور',
                    prefixIcon:
                    const Icon(
                      Icons
                          .lock_outline_rounded,
                      size:
                      19,
                    ),
                    suffixIcon:
                    IconButton(
                      onPressed:
                      _isLoading
                          ? null
                          : () {
                        setState(
                              () {
                            _obscurePassword =
                            !_obscurePassword;
                          },
                        );
                      },
                      icon:
                      Icon(
                        _obscurePassword
                            ? Icons
                            .visibility_outlined
                            : Icons
                            .visibility_off_outlined,
                        size:
                        19,
                      ),
                    ),
                  ),
                ),

                const SizedBox(
                  height:
                  26,
                ),

                SizedBox(
                  height:
                  48,
                  child:
                  ElevatedButton(
                    onPressed:
                    _isLoading
                        ? null
                        : _login,
                    style:
                    ElevatedButton
                        .styleFrom(
                      backgroundColor:
                      const Color(
                        0xFF1D1D1F,
                      ),
                      foregroundColor:
                      Colors.white,
                      shape:
                      RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius
                            .circular(
                          13,
                        ),
                      ),
                    ),
                    child:
                    _isLoading
                        ? const SizedBox(
                      width:
                      20,
                      height:
                      20,
                      child:
                      CircularProgressIndicator(
                        strokeWidth:
                        2,
                        color:
                        Colors.white,
                      ),
                    )
                        : const Text(
                      'تسجيل الدخول',
                      style:
                      TextStyle(
                        fontSize:
                        13,
                        fontWeight:
                        FontWeight
                            .w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(
                  height:
                  18,
                ),

                const Text(
                  'يتم حفظ جلسة الدخول بشكل آمن على هذا الجهاز.',
                  textAlign:
                  TextAlign.center,
                  style:
                  TextStyle(
                    fontSize:
                    10.5,
                    color:
                    AppTheme
                        .tertiaryTextColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}