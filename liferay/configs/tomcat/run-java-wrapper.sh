#!/bin/sh
set -e

PROTOCOL_KEY="-Djava.protocol.handler.pkgs="
TOMCAT_HANDLER="org.apache.catalina.webresources"
OSGI_HANDLER="org.eclipse.osgi.internal.url"
protocol_values=""

TMP_IN=$(mktemp)
TMP_OUT=$(mktemp)
trap 'rm -f "$TMP_IN" "$TMP_OUT"' EXIT
: > "$TMP_IN"
for arg in "$@"; do
    printf '%s\0' "$arg" >> "$TMP_IN"
done

set --
while IFS= read -r -d '' arg; do
    case "$arg" in
        ${PROTOCOL_KEY}*)
            value="${arg#${PROTOCOL_KEY}}"
            if [ -n "$protocol_values" ]; then
                protocol_values="${protocol_values},${value}"
            else
                protocol_values="$value"
            fi
            ;;
        *)
            set -- "$@" "$arg"
            ;;
    esac
done < "$TMP_IN"

normalize_protocols() {
    input="$1"
    normalized=""
    for token in $(printf '%s' "$input" | tr ',' ' '); do
        [ -z "$token" ] && continue
        case ",$normalized," in
            *,"$token",*) ;;
            *)
                if [ -z "$normalized" ]; then
                    normalized="$token"
                else
                    normalized="$normalized,$token"
                fi
                ;;
        esac
    done
    printf '%s' "$normalized"
}

protocol_values=$(normalize_protocols "$protocol_values")

if [ -z "$protocol_values" ]; then
    protocol_values="$TOMCAT_HANDLER,$OSGI_HANDLER"
else
    case ",$protocol_values," in
        *,$TOMCAT_HANDLER,*) ;;
        *) protocol_values="$TOMCAT_HANDLER,$protocol_values" ;;
    esac
    case ",$protocol_values," in
        *,$OSGI_HANDLER,*) ;;
        *) protocol_values="$protocol_values,$OSGI_HANDLER" ;;
    esac
    protocol_values=$(normalize_protocols "$protocol_values")
fi

: > "$TMP_OUT"
inserted=false
for arg in "$@"; do
    if [ "$inserted" = "false" ] && [ "$arg" = "-classpath" ]; then
        printf '%s\0' "${PROTOCOL_KEY}${protocol_values}" >> "$TMP_OUT"
        inserted=true
    fi
    printf '%s\0' "$arg" >> "$TMP_OUT"
done
if [ "$inserted" = "false" ]; then
    printf '%s\0' "${PROTOCOL_KEY}${protocol_values}" >> "$TMP_OUT"
fi

set --
while IFS= read -r -d '' arg; do
    set -- "$@" "$arg"
done < "$TMP_OUT"

rm -f "$TMP_IN" "$TMP_OUT"
trap - EXIT

if [ -n "$REAL_RUNJAVA" ]; then
    RUNJAVA_CMD="$REAL_RUNJAVA"
elif [ -n "$JRE_HOME" ] && [ -x "$JRE_HOME/bin/java" ]; then
    RUNJAVA_CMD="$JRE_HOME/bin/java"
elif [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    RUNJAVA_CMD="$JAVA_HOME/bin/java"
else
    RUNJAVA_CMD="java"
fi

exec "$RUNJAVA_CMD" "$@"
