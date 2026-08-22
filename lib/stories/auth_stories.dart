import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';

import '../widgets/auth_buttons.dart';

final authStories = [
  Story(
    name: 'Auth/Google Sign In',
    builder: (context) =>
        const Padding(padding: EdgeInsets.all(16), child: GoogleSignInButton()),
  ),
  Story(
    name: 'Auth/Google Sign In Loading',
    builder: (context) => const Padding(
      padding: EdgeInsets.all(16),
      child: GoogleSignInButton(loading: true),
    ),
  ),
  Story(
    name: 'Auth/Apple Sign In',
    builder: (context) =>
        const Padding(padding: EdgeInsets.all(16), child: AppleSignInButton()),
  ),
  Story(
    name: 'Auth/Apple Sign In Loading',
    builder: (context) => const Padding(
      padding: EdgeInsets.all(16),
      child: AppleSignInButton(loading: true),
    ),
  ),
];
