# robosats-web-host

https://learn.robosats.org

## Setup

Clone https://github.com/RoboSats/robosats on a searate folder

````
cd docs
docker composer up -d  # Docs
cd ../web
docker composer up -d # Tor Frontend
cd ../nodeapp 
docker composer up -d  # Clearnet Frontend
````

From this folder

````
# Make sure to manually setup certbot before
docker composer up -d
````
