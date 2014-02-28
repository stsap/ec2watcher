#!/usr/local/perlbrew/perl-5.16.3/bin/perl -w

## ec2watcher
# -- install
# yum -y install expat-devel
# cpanm Net::Amazon::EC2
# -- detail
# 起動しているec2インスタンスを通知。停止忘れの防止。

BEGIN {
    use strict;
    use warnings;
    use Net::Amazon::EC2;
    use FindBin;
    eval{ chdir $FindBin::Bin; };
    use Config::Any;
    use Email::Simple;
    use Email::Sender::Simple qw(sendmail);
    use Email::Sender::Transport::SMTP;
}

my $cfg = Config::Any->load_stems({stems => [qw(config)], use_ext => 1, flatten_to_hash => 1});
my %accessKeys = %{$cfg->{'config.json'}{'aws'}};

my @result;
my @regions = getAllRegionName(connectAWS(\%accessKeys));
foreach (@regions) {
	my %params = %accessKeys;
	$params{'region'} = $_;
    push(@result, getRunningInstances(connectAWS(\%params)));
}

my $mes = "";
foreach (@result) {
    $mes .= "[$_->{id}] ".$_->{"name"}." is running.".$/;
}
if ($mes) {
    my %alerts = %{$cfg->{'config.json'}{'alert'}};
    sendAlert({
        from => $alerts{'from'},
        to => $alerts{'to'},
        subject => $alerts{'subject'},
        message => $mes,
        sasl_host => $alerts{'sasl'}{'host'},
        sasl_port => $alerts{'sasl'}{'port'},
        sasl_username => $alerts{'sasl'}{'username'},
        sasl_password => $alerts{'sasl'}{'password'}
    });
}

## connectAWS
# AWSへ接続
# @param accessKeys [%$] アクセスキーハッシュref
# @return [$] Net::Amazon::EC2インスタンス
sub connectAWS {
	return Net::Amazon::EC2->new(shift);
}

## getRunningInstances
# 起動中のインスタンスを取得する
# @param naec2 [$] Net::Amazon::EC2インスタンス
# @return [@] 配列
# - id => インスタンスID
# - name => インスタンス名(Nameタグ値)
sub getRunningInstances {
	my $naec2 = shift;
	my @runnings;
    my $instances = $naec2->describe_instances();
	foreach (@{$instances}) {
        foreach ($_->instances_set) {
            next if ($_->instance_state->name ne "running");
            push(@runnings, {
                id => $_->instance_id,
                name => (grep({ $_->key eq "Name" } @{$_->tag_set}))[0]->value
            });
        }
	}
    return @runnings;
}

## getAllRegionName
# AWSリージョン名を全て取得
# @param naec2 [$] Net::Amazon::EC2インスタンス
# @return [@] リージョン名配列
sub getAllRegionName {
	my $naec2 = shift;
	return map({ $_->region_name; } @{$naec2->describe_regions()});
}

## 
# @param mail [hashref]
# - message [string] 
# - to [string]
# - from [string] 
# - subject [string]
# - sasl_host [string]
# - sasl_port [number]
# - sasl_username [string]
# - sasl_password [string]
#
sub sendAlert {
    my $mail = shift;
    my $email = Email::Simple->create(
        header => [
            To => join(',', @{$mail->{'to'}}),
            From => $mail->{'from'},
            Subject => $mail->{'subject'}
        ],
        body => $mail->{'message'}
    );
    sendmail($email, {
        transport => Email::Sender::Transport::SMTP->new({
            ssl => 1,
            host => $mail->{'sasl_host'},
            port => $mail->{'sasl_port'},
            sasl_username => $mail->{'sasl_username'},
            sasl_password => $mail->{'sasl_password'}
        })
    });
}

