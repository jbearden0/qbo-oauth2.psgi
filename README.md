# qbo-oauth2.psgi
## Purpose: Demonstrates accessing Intuit API via OAuth2 and perl.
## License: Use at your own risk. If you like it maybe buy me a beer sometime.
## Notes:
 * This code tries to minimize the use of libraries.
 * This code tries to maximize readability to better convey concepts.
 * This code looks nothing like my production code.
 * This code does not show the disconnect endpoint, which you should implement.
 * Plack is used because I am most familiar with it.
 * If you try to contact me I may not help you or even reply.
## General Gotchas:
 * Ensure the authentication values do not contain newlines.
 * If you POST then you need to submit the parameters in the body.
 * When accessing the API the URL changes for production VS sandbox.
 * You can only use localhost for the redirect URL in the sandbox.
## To install and run:
 * apt-get install libplack-perl libplack-middleware-session-perl
 * Add redirect URI on QBO app keys tab.
 * Update $Params from QBO app keys tab.
 * plackup -r qbo-oauth2.psgi
 * http://localhost:5000/
