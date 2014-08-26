#!/bin/sh

#Requires imagemagick is installed with HomeBrew
#  brew install imagemagick


MONGO_PROD_HOST='rs0/mongo01.prd.nymetro.com'
MONGO_QA_HOST='rs0/mongo01.qa.nymetro.com'
MONGO_PORT='27017'
MONGO_DATABASE='articles'
COLLECTION='articles'
TIMESTAMP_YESTERDAY=`python -c 'import time; print int((time.time()-(86400*2))*1000)'`
TIMESTAMP_TODAY=`python -c 'import time; print int(time.time()*1000)'`
MONGO_OUT='vulture_prod_today.json'
MONGO_TEMP='vulture_qa_today.json'
QUERY="'{blogName:\"Vulture\", publishDate: {\$gte: new Date($TIMESTAMP_YESTERDAY)}'"
IMAGES_PROD="http://mediaplay.prd.nymetro.com/imgs"
IMAGES_QA="http://mediaplay.qa.nymetro.com/imgs"
MAX_TIME='3'
MAX_TIME_POST='10'

#Transfer articles
echo $QUERY
mongoexport --host $MONGO_PROD_HOST --db $MONGO_DATABASE --collection $COLLECTION --query "{blogName:'Vulture', publishDate: {\$gte: new Date($TIMESTAMP_YESTERDAY)}}" --out $MONGO_OUT
sed -e 's#http://www.vulture.com#http://www.qa.vulture.com#g' $MONGO_OUT > $MONGO_TEMP
mongoimport --upsert --host $MONGO_QA_HOST --db $MONGO_DATABASE --collection $COLLECTION --file vulture_qa_today.json

#Get feeds
curl "http://api.nymag.com/content/vulture/mostviewed/lastDay" -o most-popular.json
curl "http://fivepointswsgi.qa.nymetro.com:9001/content/article/?brand=vulture&limit=30" -o top-stories.json

#Get list of images
perl -ne 'print "$1\n" while (/content\/dam\/(.*?(jpg|png))/igs)' vulture_qa_today.json | sort | uniq > images.txt
perl -ne 'print "$1\n" while (/content\/dam\/(.*?(jpg|png))/igs)' most-popular.json | sort | uniq >>images.txt
perl -ne 'print "$1\n" while (/content\/dam\/(.*?(jpg|png))/igs)' top-stories.json | sort | uniq >>images.txt

#Download images
for file in $(cat images.txt) ; do
	echo $file
	curl -m $MAX_TIME -s -O "$IMAGES_PROD/$file" -w "%{filename_effective}" >filename.txt
	
	echo "$file" | perl -ne 'print "$1\n" while (/(.*)\/.*?(jpg|png)/igs)' >path.txt
	cat path.txt
	echo
	cat filename.txt
	echo
	FILEPATH=$(cat path.txt)
	FILENAME=$(cat filename.txt)
	echo "curl -m $MAX_TIME -If $IMAGES_QA/$FILEPATH/$FILENAME -w '%{http_code}'"
	convert "$FILENAME" -sepia-tone 80% -resize '300' "$FILENAME"
	curl -m $MAX_TIME -If "$IMAGES_QA/$FILEPATH/$FILENAME" -w "%{http_code}"
	if [ $? -ne 0 ] ; then
		curl -m $MAX_TIME_POST -v -s -X POST -b 'user={"username":"test","groups":[]}' -FuploadPath="$FILEPATH" -Fthisparamdoesnotmatter="@$FILENAME" http://mediaplay.qa.nymetro.com/admin/imgs/
	fi
	cat filename.txt | xargs rm
	cat path.txt | xargs rm
done




