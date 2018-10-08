#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use JSON::XS;
use LWP::UserAgent ();
use MIME::Base64;
use Plack::Builder;
use Plack::Middleware::Session;
use Plack::Request;
use Plack::Response;
use URI::Escape qw(uri_escape);

# Purpose: Demonstrates accessing Intuit API via OAuth2 and perl.
# License: Use at your own risk. If you like it maybe buy me a beer sometime.
# Author: James D Bearden james@nontrivial.net
# Notes:
 # This code tries to minimize the use of libraries.
 # This code tries to maximize readability to better convey concepts.
 # This code looks nothing like my production code.
 # This code does not show the disconnect endpoint, which you should implement.
 # Plack is used because I am most familiar with it.
 # If you try to contact me I may not help you or even reply.
# Gotchas:
 # Ensure the authentication values do not contain newlines.
 # If you POST then you need to submit the parameters in the body.
 # When accessing the API the URL changes for production VS sandbox.
 # You can only use localhost for the redirect URL in the sandbox.
# Hints:
 # apt-get install libplack-perl libplack-middleware-session-perl
 # Add redirect URI on QBO app keys tab.
 # Update $Params below from QBO app keys tab.
 # plackup -r qbo-oauth2.psgi
 # http://localhost:5000/

my $Params = {
  AppClientID => '', # Get this from Intuit developer app settings.
  AppSecret => '',   # Get this from Intuit developer app settings.
  RealmID => '',     # Get this from Intuit developer app settings.
  AppScope => 'com.intuit.quickbooks.accounting',
  RedirectURI => 'http://localhost:5000/qbo',
  TransID => 'SomeUniqueTransactionIdentifier'
};
$Data::Dumper::Sortkeys = 1;

#------------------------------------------------------------------------------
sub HandleResponse {
  my ($Request) = @_;

  my @PathChunks = split(/\//, $Request->path_info());
  my $Session = $Request->session();
  my $Content = 'Got request: ' . $Request->path_info();
  my ($Status,$Headers) = (200,{ 'Content-Type' => 'text/html' });

  if ($PathChunks[1] && uc($PathChunks[1]) eq 'GETAUTH') { # Step 1
    # Ask Intuit to ask the end user for authentication.
    my $Redirect = 'https://appcenter.intuit.com/connect/oauth2?redirect_uri=' .
      uri_escape($Params->{RedirectURI}) . '&scope=' .
      uri_escape($Params->{AppScope}) . '&state=' .
      uri_escape($Params->{TransID}) . '&client_id=' .
      uri_escape($Params->{AppClientID}) . '&response_type=code';

    print("Redirecting to: $Redirect\n");
    ($Status, $Headers) = (302, { 'Location' => $Redirect });
  } elsif ($PathChunks[1] && uc($PathChunks[1]) eq 'QBO') { # Step 2
    # Handle the authentication response from Intuit.
    my $Result = $Request->parameters->as_hashref;
    if ($Result->{realmId} && $Result->{code}) {
      print("Got authentication code: $Result->{code}\n");

      my $URL = 'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer';
      my $BasicAuth = encode_base64( $Params->{AppClientID} . ':' .
				     $Params->{AppSecret}, '' );
      my $Headers = HTTP::Headers->new(
	'Accept'        => 'application/json',
	'Authorization' => "Basic $BasicAuth", # Ensure no newlines
	'Content-Type'  => 'application/x-www-form-urlencoded',
	'Host'          => 'oauth.platform.intuit.com'
	);

      my $UA = LWP::UserAgent->new();
      $UA->timeout(60);
      $UA->default_headers($Headers);

      my $Submits = { redirect_uri => $Params->{RedirectURI},
		      state => $Params->{TransID},
		      code => $Result->{code},
		      grant_type => 'authorization_code'
      };

      my $Res = $UA->post($URL, $Submits);
      if ($Res->is_success) {
	my $Access = JSON::XS->new->decode($Res->decoded_content);
	$Session->{AccessToken} = $Access->{access_token}; # Good for 60 minutes

	# This value should be stored more securely.
	$Session->{RealmID} = $Result->{realmId};

	# This value should be encrypted and stored more securely.
	$Session->{RefreshToken} = $Access->{refresh_token}; # Good for 100 days

	if ($Session->{AccessToken}) {
	  print("Got access token: $Session->{AccessToken}\n");
	  $Content = "Got access token '$Session->{AccessToken}' for " .
	    "RealmID '$Session->{RealmID}' using authentication code " .
	    "'$Session->{AuthCode}'. Authorization will last for 1 hour.<BR>" .
	    '<A HREF="/getdata">Get company data</A><BR>' .
	    '<A HREF="/refresh">Refresh access token</A>';
	} else { $Content = "Unable to get an access token from code!";}
      } elsif ($Res->code == 401) {
	$Content = 'Need to <A HREF="/refresh">refresh the access token</A>!';
      } else {
	$Content = 'Got error code ' . $Res->code . ' (' . $Res->message .
	  ') from Intuit when asking for access token!';
      }
    } else { $Content = "Got invalid response from Intuit!"; }
  } elsif ($PathChunks[1] && uc($PathChunks[1]) eq 'REFRESH') { # Step 3
    # Refresh the access token.
    my $URL = 'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer';
    my $BasicAuth = encode_base64( $Params->{AppClientID} . ':' .
				   $Params->{AppSecret}, '' );
    my $Headers = HTTP::Headers->new(
      'Accept'        => 'application/json',
      'Authorization' => "Basic $BasicAuth", # Ensure no newlines
      'Content-Type'  => 'application/x-www-form-urlencoded',
      'Host'          => 'oauth.platform.intuit.com',
      'Cache-Control' => 'no-cache'
      );

    my $UA = LWP::UserAgent->new();
    $UA->timeout(60);
    $UA->default_headers($Headers);

    my $Submits = { refresh_token => $Session->{RefreshToken},
		    grant_type => 'refresh_token'
    };

    my $Res = $UA->post($URL, $Submits);
    if ($Res->is_success) {
      my $Access = JSON::XS->new->decode($Res->decoded_content);
      $Session->{AccessToken} = $Access->{access_token}; # Good for 60 minutes

      # This value should be encrypted and stored more securely.
      $Session->{RefreshToken} = $Access->{refresh_token}; # Good for 100 days

      if ($Session->{AccessToken}) {
	print("Got access token: $Session->{AccessToken}\n");
	$Content = "Got access token '$Session->{AccessToken}' for " .
	  "RealmID '$Session->{RealmID}' using old refresh token. " .
	  "Authorization will last for 1 hour.<BR>" .
	  '<A HREF="/getdata">Get company data</A><BR>' .
	  '<A HREF="/refresh">Refresh access token</A>';
      } else { $Content = "Unable to refresh access token!";}
    } else {
      $Content = 'Got error code ' . $Res->code . ' (' . $Res->message .
	') from Intuit when asking for access token!';
    }
  } elsif ($PathChunks[1] && uc($PathChunks[1]) eq 'GETDATA') { # Step 4
    # Use API to get example data.
    my $URL = 'https://sandbox-quickbooks.api.intuit.com'; # Good for sandbox
    my $EP = "/v3/company/$Session->{RealmID}/companyinfo/$Session->{RealmID}";
    my $Headers = HTTP::Headers->new(
      'Accept'        => 'application/json',
      'Authorization' => "Bearer $Session->{AccessToken}",
      'Content-Type'  => 'application/json;charset=UTF-8',
      );

    my $UA = LWP::UserAgent->new();
    $UA->timeout(60);
    $UA->default_headers($Headers);

    my $Res = $UA->get($URL . $EP);

    if ($Res->is_success) {
      print("Got example data\n");
      $Content = 'Got:<PRE>' .
	Dumper(JSON::XS->new->decode($Res->decoded_content)) . '</PRE><BR>' .
	'<A HREF="/getdata">Get company data</A><BR>' .
	'<A HREF="/refresh">Refresh access token</A>';
    } elsif ($Res->code == 401) {
      $Content = 'Need to <A HREF="/refresh">refresh the access token</A>!';
    } else {
      $Content = 'Got error code ' . $Res->code . ' (' . $Res->message .
	') from Intuit when asking for company data!';
    }
  } else { # Step 0
    # If all else fails assume we are just starting.
    if ($Params->{AppClientID} && $Params->{AppSecret} && $Params->{AppScope}) {
      $Content = '<A HREF="/getauth">Request authentication code</A>';
    } else { $Content = "You need to enter the application parameters!"; }
  }

  $Content = '<HTML><HEAD><TITLE>QBO OAUTH2 DEMO</TITLE></HEAD><BODY>' .
    '<H1>QBO OAUTH2 DEMO</H1>' . $Content . '</BODY></HTML>';

  return Plack::Response->new($Status, $Headers, $Content)->finalize();
}

#------------------------------------------------------------------------------
# Below here is plack magic.
#------------------------------------------------------------------------------
my $app = sub {
  my $Env = shift;

  return HandleResponse(Plack::Request->new($Env));
};
#------------------------------------------------------------------------------
#use Plack::Builder;
builder {
  enable 'Session::Cookie', secret => 'lE7o3SDesm0cUKvOzcWt8PYlt9lNDrC1YMu28OK';
  enable "StackTrace";

  $app;
};
