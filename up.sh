#!/usr/bin/expect
set timeout 30
spawn rm -rf /Users/farmerjohn/new_blog_public
spawn  cp -rf ./public/ /Users/farmerjohn/new_blog_public
spawn cd /Users/farmerjohn/new_blog_public
spawn git add -A
spawn git commit -m \"update\" 
spawn git push deploy --force
expect "*password*"
send "Farmercoding992#\r"
