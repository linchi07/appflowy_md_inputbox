import 'package:flutter/material.dart';

void main() {
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Container(
            color: Colors.red,
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (context) => Container(
                    height: 50,
                    width: 50,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
