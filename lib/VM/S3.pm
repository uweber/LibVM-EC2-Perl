package VM::S3;

use strict;
use base 'VM::EC2';
use AnyEvent::HTTP;
use HTTP::Request::Common;
use Digest::SHA 'sha256_hex','hmac_sha256','hmac_sha256_hex';
use Carp 'croak';

VM::EC2::Dispatch->register(
    ''   => sub {VM::EC2::Dispatch::load_module('VM::S3::BucketList');
		 my $bl =  VM::S3::BucketList->new(@_);
		 return $bl ? $bl->buckets : undef
    },
    'get bucket' => 'VM::S3::Generic',
    );

sub get_service {
    my $self     = shift;
    my $action   = shift || '';
    my $endpoint = shift || 'https://s3.amazonaws.com';
    local $self->{endpoint} = $endpoint;
    local $self->{version}  = '2006-03-01';
    my $request = GET($self->endpoint.'/',
		      Host=>URI->new($self->endpoint)->host,
		      'X-Amz-Content-Sha256'=>sha256_hex('')
	);
    AWS::Signature4->new(-access_key=>$self->access_key,
			 -secret_key=>$self->secret)->sign($request);
    my $cv = $self->async_request($action,$request);
    if ($VM::EC2::ASYNC) {
	return $cv;
    } else {
	return $cv->recv();
    }
}

sub list_buckets {
    my $self = shift;
    return $self->get_service();
}

sub get_bucket {
    my $self   = shift;
    my $bucket = shift;
    $self->get_service('get bucket',"https://$bucket.s3.amazonaws.com");
}

1;



