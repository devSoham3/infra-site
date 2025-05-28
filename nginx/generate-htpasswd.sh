#!/bin/bash
htpasswd -bc /etc/nginx/conf.d/.htpasswd "${MONITORING_USER}" "${MONITORING_PASSWORD}"
nginx -g 'daemon off;'