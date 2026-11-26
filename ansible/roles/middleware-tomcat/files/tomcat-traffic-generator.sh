#!/usr/bin/env bash
while true; do
  curl -s -o /dev/null "http://localhost:8080/examples/servlets/servlet/HelloWorldExample"
  curl -s -o /dev/null "http://localhost:8080/examples/jsp/jsp2/el/basic-arithmetic.jsp"
  sleep 3
done
