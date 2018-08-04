cp -rf ./public/* ../new_blog_public
cd ../new_blog_public
git add -A 
git commit -m "update"
git push deploy --force
