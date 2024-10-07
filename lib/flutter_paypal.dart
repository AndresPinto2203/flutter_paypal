library flutter_paypal;

import 'dart:core';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Import for Android features.
import 'package:webview_flutter_android/webview_flutter_android.dart';
// Import for iOS features.
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'src/PaypalServices.dart';
import 'src/errors/network_error.dart';
import 'src/screens/complete_order.dart';

class UsePaypal extends StatefulWidget {
  final Function onSuccess, onCancel, onError;
  final String returnURL, cancelURL, note, clientId, secretKey;
  // model purchaseUnits example: [{{"reference_id": "d9f80740-38f0-11e8-b467-0ed5f89f718b","amount": {"currency_code": "USD","value": "100.00"}}}]
  final List purchaseUnits;
  final bool sandboxMode;
  final String? intent; // CAPTURE || AUTHORIZE
  final String? brandName;
  final String?
      shippingPreference; // GET_FROM_FILE || NO_SHIPPING || SET_PROVIDED_ADDRESS
  final String? landingPage; // LOGIN || GUEST_CHECKOUT || NO_PREFERENCE
  final String? userAction;
  final String?
      paymentMethodPreference; // UNRESTRICTED || IMMEDIATE_PAYMENT_REQUIRED
  final String? locale; // BCP 47-formatted locale code (e.g. en-US)
  final bool onlyCreateOrder;

  const UsePaypal({
    Key? key,
    required this.onSuccess,
    required this.onError,
    required this.onCancel,
    required this.returnURL,
    required this.cancelURL,
    required this.clientId,
    required this.secretKey,
    this.intent = 'CAPTURE',
    this.sandboxMode = false,
    this.note = '',
    this.brandName = '',
    this.shippingPreference = 'GET_FROM_FILE',
    this.landingPage = 'NO_PREFERENCE',
    this.userAction = 'CONTINUE',
    this.paymentMethodPreference = 'UNRESTRICTED',
    this.locale = 'en-US',
    this.purchaseUnits = const [],
    this.onlyCreateOrder = false,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return UsePaypalState();
  }
}

class UsePaypalState extends State<UsePaypal> {
  late final WebViewController _controller;
  String checkoutUrl = '';
  String navUrl = '';
  String executeUrl = '';
  String accessToken = '';
  bool loading = true;
  bool pageLoading = true;
  bool loadingError = false;
  late PaypalServices services;
  int pressed = 0;
  final Map<dynamic, dynamic> resultReqOrderData = {};

  Map getOrderData() {
    Map<String, dynamic> temp = {
      "intent": widget.intent,
      "purchase_units": widget.purchaseUnits,
      "payment_source": {
        'paypal': {
          'experience_context': {
            'payment_method_preference': widget.paymentMethodPreference,
            'brand_name': widget.brandName,
            'locale': widget.locale,
            'landing_page': widget.landingPage,
            'shipping_preference': widget.shippingPreference,
            'user_action': widget.userAction,
            "return_url": widget.returnURL,
            "cancel_url": widget.cancelURL
          },
        },
      }
    };
    return temp;
  }

  loadOrder() async {
    setState(() {
      loading = true;
    });
    try {
      Map getToken = await services.getAccessToken();
      if (getToken['token'] != null) {
        accessToken = getToken['token'];
        final orderData = getOrderData();
        final res = await services.createPaypalOrder(orderData, accessToken);
        if (res["payerActionUrl"] != null) {
          setState(() {
            resultReqOrderData.addAll(res);
            executeUrl = res["selfUrl"];
            loading = false;
            pageLoading = false;
            loadingError = false;
          });
          _controller
              .loadRequest(Uri.parse(resultReqOrderData['payerActionUrl']));
        } else {
          widget.onError(res);
          setState(() {
            loading = false;
            pageLoading = false;
            loadingError = true;
          });
        }
      } else {
        widget.onError("${getToken['message']}");

        setState(() {
          loading = false;
          pageLoading = false;
          loadingError = true;
        });
      }
    } catch (e) {
      widget.onError(e);
      setState(() {
        loading = false;
        pageLoading = false;
        loadingError = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    services = PaypalServices(
      sandboxMode: widget.sandboxMode,
      clientId: widget.clientId,
      secretKey: widget.secretKey,
    );
    setState(() {
      navUrl = widget.sandboxMode
          ? 'https://api.sandbox.paypal.com'
          : 'https://www.api.paypal.com';
    });
    // Enable hybrid composition.
    loadOrder();

    // #docregion platform_features
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller =
        WebViewController.fromPlatformCreationParams(params);
    // #enddocregion platform_features

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            debugPrint('WebView is loading (progress : $progress%)');
          },
          onPageStarted: (String url) {
            setState(() {
              pageLoading = true;
              loadingError = false;
            });
            debugPrint('Page started loading: $url');
          },
          onPageFinished: (String url) {
            setState(() {
              navUrl = url;
              pageLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('''
              Page resource error:
              code: ${error.errorCode}
              description: ${error.description}
              errorType: ${error.errorType}
              isForMainFrame: ${error.isForMainFrame}
          ''');
          },
          onNavigationRequest: (NavigationRequest request) async {
            if (request.url.startsWith('https://www.youtube.com/')) {
              debugPrint('blocking navigation to ${request.url}');
              return NavigationDecision.prevent;
            }
            if (request.url.contains(widget.returnURL)) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => CompleteOrder(
                    url: request.url,
                    services: services,
                    executeUrl: executeUrl,
                    accessToken: accessToken,
                    onSuccess: widget.onSuccess,
                    onCancel: widget.onCancel,
                    onError: widget.onError,
                    intent: widget.intent ?? 'CAPTURE',
                    onlyCreateOrder: widget.onlyCreateOrder,
                  ),
                ),
              );
            }
            if (request.url.contains(widget.cancelURL)) {
              final uri = Uri.parse(request.url);
              await widget.onCancel(uri.queryParameters);
              // ignore: use_build_context_synchronously
              Navigator.of(context).pop();
            }
            debugPrint('allowing navigation to ${request.url}');
            return NavigationDecision.navigate;
          },
          onUrlChange: (UrlChange change) {
            debugPrint('url change to ${change.url}');
          },
        ),
      )
      ..addJavaScriptChannel(
        'Toaster',
        onMessageReceived: (JavaScriptMessage message) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message.message)),
          );
        },
      );

    // #docregion platform_features
    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    // #enddocregion platform_features

    _controller = controller;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (pressed < 2) {
          setState(() {
            pressed++;
          });
          final snackBar = SnackBar(
              content: Text(
                  'Press back ${3 - pressed} more times to cancel transaction'));
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
          return false;
        } else {
          return true;
        }
      },
      child: Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF272727),
            leading: GestureDetector(
              child: const Icon(Icons.arrow_back_ios),
              onTap: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                Expanded(
                    child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        color: Uri.parse(navUrl).hasScheme
                            ? Colors.green
                            : Colors.blue,
                        size: 18,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          navUrl,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      SizedBox(width: pageLoading ? 5 : 0),
                      pageLoading
                          ? const SpinKitFadingCube(
                              color: Color(0xFFEB920D),
                              size: 10.0,
                            )
                          : const SizedBox()
                    ],
                  ),
                ))
              ],
            ),
            elevation: 0,
          ),
          body: SizedBox(
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            child: loading
                ? const Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: SpinKitFadingCube(
                            color: Color(0xFFEB920D),
                            size: 30.0,
                          ),
                        ),
                      ),
                    ],
                  )
                : loadingError
                    ? Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: NetworkError(
                                  loadData: loadOrder,
                                  message: "Something went wrong,"),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: WebViewWidget(controller: _controller),
                          ),
                        ],
                      ),
          )),
    );
  }
}
