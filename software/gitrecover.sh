file=$1
git checkout $(git rev-list -n 1 HEAD -- "$file")^ -- "$file"
