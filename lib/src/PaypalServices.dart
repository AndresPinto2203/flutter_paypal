// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert' as convert;
import 'package:http_auth/http_auth.dart';

class PaypalServices {
  final String clientId, secretKey;
  final bool sandboxMode;
  PaypalServices({
    required this.clientId,
    required this.secretKey,
    required this.sandboxMode,
  });

  getAccessToken() async {
    String domain = sandboxMode
        ? "https://api.sandbox.paypal.com"
        : "https://api.paypal.com";
    try {
      var client = BasicAuthClient(clientId, secretKey);
      var response = await client.post(
          Uri.parse("$domain/v1/oauth2/token?grant_type=client_credentials"));
      if (response.statusCode == 200) {
        final body = convert.jsonDecode(response.body);
        return {
          'error': false,
          'message': "Success",
          'token': body["access_token"]
        };
      } else {
        return {
          'error': true,
          'message': "Your PayPal credentials seems incorrect"
        };
      }
    } catch (e) {
      return {
        'error': true,
        'message': "Unable to proceed, check your internet connection."
      };
    }
  }

  Future<Map> createPaypalPayment(transactions, accessToken) async {
    String domain = sandboxMode
        ? "https://api.sandbox.paypal.com"
        : "https://api.paypal.com";
    try {
      var response = await http.post(Uri.parse("$domain/v1/payments/payment"),
          body: convert.jsonEncode(transactions),
          headers: {
            "content-type": "application/json",
            'Authorization': 'Bearer $accessToken'
          });

      final body = convert.jsonDecode(response.body);
      if (response.statusCode == 201) {
        if (body["links"] != null && body["links"].length > 0) {
          List links = body["links"];

          String executeUrl = "";
          String approvalUrl = "";
          final item = links.firstWhere((o) => o["rel"] == "approval_url",
              orElse: () => null);
          if (item != null) {
            approvalUrl = item["href"];
          }
          final item1 = links.firstWhere((o) => o["rel"] == "execute",
              orElse: () => null);
          if (item1 != null) {
            executeUrl = item1["href"];
          }
          return {"executeUrl": executeUrl, "approvalUrl": approvalUrl};
        }
        return {};
      } else {
        return body;
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map> executePayment(url, payerId, accessToken) async {
    try {
      var response = await http.post(Uri.parse(url),
          body: convert.jsonEncode({"payer_id": payerId}),
          headers: {
            "content-type": "application/json",
            'Authorization': 'Bearer $accessToken'
          });

      final body = convert.jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'error': false, 'message': "Success", 'data': body};
      } else {
        return {
          'error': true,
          'message': "Payment inconclusive.",
          'data': body
        };
      }
    } catch (e) {
      return {'error': true, 'message': e, 'exception': true, 'data': null};
    }
  }

  Future<Map> createPaypalOrder(ordetData, String accessToken) async {
    String domain = sandboxMode
        ? "https://api.sandbox.paypal.com"
        : "https://api.paypal.com";
    try {
      var response = await http.post(Uri.parse("$domain/v2/checkout/orders"),
          body: convert.jsonEncode(ordetData),
          headers: {
            "content-type": "application/json",
            'Authorization': 'Bearer $accessToken'
          });

      final body = convert.jsonDecode(response.body);
      debugPrint("body: $body");
      if (response.statusCode == 201 || response.statusCode == 200) {
        if (body["links"] != null && body["links"].length > 0) {
          List links = body["links"];

          String payerActionUrl = "";
          String selfUrl = "";
          final item =
              links.firstWhere((o) => o["rel"] == "self", orElse: () => null);
          if (item != null) {
            selfUrl = item["href"];
          }
          final item1 = links.firstWhere((o) => o["rel"] == "payer-action",
              orElse: () => null);
          if (item1 != null) {
            payerActionUrl = item1["href"];
          }
          return {
            'id': body['id'],
            'status': body['status'],
            'paymentSource': body['payment_source'],
            "payerActionUrl": payerActionUrl,
            "selfUrl": selfUrl
          };
        }
        return {};
      } else {
        return body;
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map> confirmOrder(url, payerId, accessToken, String intent, bool onlyCreateOrder) async {
    try {
      //Get order data
      var orderDataResp = await http.get(Uri.parse(url), headers: {
        "content-type": "application/json",
        'Authorization': 'Bearer $accessToken'
      });

      final orderData = convert.jsonDecode(orderDataResp.body);

      //Confirm order
      var confirmOrderResp = await http.post(
          Uri.parse('$url/confirm-payment-source'),
          body: convert
              .jsonEncode({"payment_source": orderData['payment_source']}),
          headers: {
            "content-type": "application/json",
            'Authorization': 'Bearer $accessToken'
          });

      final confirmOrderData = convert.jsonDecode(confirmOrderResp.body);

      if (onlyCreateOrder) {
        return {
          'error': false,
          'message': "Success",
          'data': {
            'orderData': orderData,
            'confirmOrderData': confirmOrderData
          },
        };
      }

      //Authorize payment

      var response = await http.post(Uri.parse('$url/${intent == 'CAPTURE' ? 'capture' : 'authorize'}'),
          body: convert.jsonEncode({"payer_id": payerId}),
          headers: {
            "content-type": "application/json",
            'Authorization': 'Bearer $accessToken'
          });

      final body = convert.jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'error': false,
          'message': "Success",
          'data': {
            'orderData': orderData,
            'confirmOrderData': confirmOrderData,
            'paymentData': body
          },
        };
      } else {
        return {
          'error': true,
          'message': "Payment inconclusive.",
          'data': body
        };
      }
    } catch (e) {
      return {'error': true, 'message': e, 'exception': true, 'data': null};
    }
  }
}
