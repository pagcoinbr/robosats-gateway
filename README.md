# robosats-web-host

https://learn.robosats.org

## Setup

Clone https://github.com/RoboSats/robosats on a searate folder

````
cd robosats
docker run -d --name pages --restart always -p 4000:4000 pages
cd web
docker composer up -d
````

From this folder

````
docker composer up -d
````