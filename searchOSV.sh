#!/bin/bash
# copyright 2026 @owlapprentice on Github
set -Eeuo pipefail

if [[ $# -ne 1 || -z "${1:-}" ]]; then
    echo "Usage: $0 KEYWORD | --download" >&2
    exit 1
fi

SCRIPT_PATH="$(realpath -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname -- "${SCRIPT_PATH}")"
WORK_DIR="${SCRIPT_DIR}/data.searchOSV"
ZIP_FILE="${WORK_DIR}/all.zip"
INDEX_FILE="${WORK_DIR}/index.zst"

KEYWORD="$1"

print_msg() {
    echo "$(date +"%Y-%m-%d(%a) %T")" "$*"
}
print_msg_nolf() {
    if [[ -t 1 ]]; then
        printf '\r\033[K%s %s\r' "$(date +"%Y-%m-%d(%a) %T")" "$*"
    else
        printf '%s %s\n' "$(date +"%Y-%m-%d(%a) %T")" "$*"
    fi
}

alert_old_indexfile() {
    local file="$1"
    local time_limit=$((18 * 60 * 60))
    local file_mtime now

    if [[ ! -f "$file" ]] ; then
        print_msg "検索用インデックス ${file} が見つかりません。"
        return 2
    fi

    file_mtime="$(stat -c '%Y' -- "$file")"
    now="$(date +%s)"
    if (( now - file_mtime >= time_limit )) ;  then
        local hours=$(( (now - file_mtime) / (60 * 60) ))
        _show_alert() {
            print_msg "*** WARNING *** : 検索用インデックス ${file} は ${hours} 時間以上前に更新されたものです。"
            print_msg "*** WARNING *** : ${SCRIPT_PATH} --download を実行して検索用インデックス ${file} を更新してください。"
        }
        _show_alert
        if [[ ! -t 1 || ! -t 2 ]]; then
            _show_alert >&2
        fi
    fi
    return 0
}

if [[ "${KEYWORD}" == "--download" || ${KEYWORD} == "--extract" ]]; then
    mkdir -p -- "$WORK_DIR"

    TEMP_ZIP="$(mktemp "${WORK_DIR}/all.zip.tmp.XXXXXX")"
    TEMP_DB="$(mktemp -d "${WORK_DIR}/db.tmp.XXXXXX")"
    TEMP_INDEX="$(mktemp "${INDEX_FILE}.tmp.XXXXXX")"
    TEMP_INDEX_ZIP="$(mktemp "${INDEX_FILE}.zipped.tmp.XXXXXX")"
    _cleanup() {
        [[ -n "${TEMP_ZIP:-}" && -e "${TEMP_ZIP}" ]] && rm -f -- "${TEMP_ZIP}"
        [[ -n "${TEMP_DB:-}"  && -e "${TEMP_DB:-}" ]] && rm -rf -- "${TEMP_DB}"
        [[ -n "${TEMP_INDEX:-}"  && -e "${TEMP_INDEX:-}" ]] && rm -f -- "${TEMP_INDEX}"
        [[ -n "${TEMP_INDEX_ZIP:-}"  && -e "${TEMP_INDEX_ZIP:-}" ]] && rm -f -- "${TEMP_INDEX_ZIP}"
    }
    trap _cleanup EXIT

    if [[ "${KEYWORD}" == "--download" ]] ; then
        print_msg "データベースをダウンロードします。" >&2
        if ! curl -fL --retry 3 \
            'https://storage.googleapis.com/osv-vulnerabilities/all.zip' \
            -o "${TEMP_ZIP}"; then

            print_msg "データベースのダウンロードに失敗しました。" >&2
            exit 1
        fi

        if ! unzip -tq "${TEMP_ZIP}" >/dev/null 2>&1; then
            print_msg "ダウンロードしたZIPファイルが破損しています: ${TEMP_ZIP}" >&2
            exit 1
        fi
        mv -- "${TEMP_ZIP}" "${ZIP_FILE}"
	TEMP_ZIP=""
        print_msg "データベースのダウンロードに成功しました。"
    fi

    print_msg "データベースを展開します。"
    if [[ ! -f "${ZIP_FILE}" ]]; then
        print_msg "展開対象のZIPファイルが存在しません: ${ZIP_FILE}" >&2
        exit 1
    fi
    if ! unzip -q "${ZIP_FILE}" -d "${TEMP_DB}"; then
        print_msg "データベースの展開に失敗しました。" >&2
        exit 1
    fi

    # TEMP_DB内にJSONが存在することを確認
    FIRST_JSON="$(find "${TEMP_DB}" -type f -name '*.json' -print -quit)"
    if [[ -z "${FIRST_JSON}" ]]; then
        print_msg "展開先にJSONファイルが存在しません。" >&2
        exit 1
    fi
    print_msg "データベースの展開に成功しました。"
    
    print_msg "検索用インデックスを作成します。20～30分以上の時間が必要です。"
    printf '%s\n' \
        $'osv_id\tsummary\tecosystem_name\tpurl\tcpe\taliases' \
        > "${TEMP_INDEX}"

    JQ_DIRECTIVE="$( sed '1,/^###[[:space:]]*JQ[[:space:]]*###/d' "${SCRIPT_PATH}" )"
    find "${TEMP_DB}" \
         -type f \
         -name '*.json' \
         -print0 \
    | xargs -0 -r jq -r \
         "${JQ_DIRECTIVE}" \
         -- \
    >> "${TEMP_INDEX}"
    
    rm -rf -- "${TEMP_DB}"
    TEMP_DB=""

    if ! zstd -19 -T0 -f -o "${TEMP_INDEX_ZIP}" -- "${TEMP_INDEX}" ; then
	rm -f -- "${TEMP_INDEX_ZIP}"
        print_msg "検索用インデックスの作成・圧縮に失敗しました。" >&2
        exit 1
    fi
    mv -f -- "${TEMP_INDEX_ZIP}"  "${INDEX_FILE}"
    TEMP_INDEX_ZIP=""
    rm -f -- "${TEMP_INDEX}"
    TEMP_INDEX=""

    print_msg "検索用インデックスの作成に成功しました。"
    print_msg "「$0 検索キーワード」の実行が可能になりました。"
    exit 0
fi

if [[ ! -f "${INDEX_FILE}" ]]; then
    print_msg "検索用インデックスが存在しません。先に '$0 --download' を実行してください。" >&2
    exit 1
fi

alert_old_indexfile "${INDEX_FILE}"

RG_COLOR='never'
if [[ -t 1 ]]; then
    RG_COLOR='always'
fi

if rg \
    --search-zip \
    --no-line-number \
    --fixed-strings \
    --ignore-case \
    --color="${RG_COLOR}" \
    -- "${KEYWORD}" "${INDEX_FILE}" \
    | sed 'G' # as inserting an extra line-break after each line.
then
    :
else
    RG_STATUS="${PIPESTATUS[0]}"
    if (( RG_STATUS == 1 )); then
        print_msg "マッチするものはありませんでした。"
    elif (( RG_STATUS != 0 )); then
        print_msg "検索中にエラーが発生しました。" >&2
	exit "${RG_STATUS}"
    fi
fi

alert_old_indexfile "${INDEX_FILE}"  #警告は末尾にも表示する

exit 0

: <<'### EOF ###'
### JQ ###
    # CPE形式の文字列を抽出する。
    # CPEはOSV標準項目ではないため、存在する場合だけ取得する。
    def cpe_strings($x):
	[
		$x
		    | ..
			| strings
			| select(test("^(cpe:/|cpe:2\\.3:)"; "i"))
		]
	| unique;

    # withdrawn済みの脆弱性は除外
    select(.withdrawn == null)
	
	    | . as $v
	
	    # 影響パッケージを1脆弱性1行にまとめる
	    | (
		[
			$v.affected[]?.package?
			    | "\(.ecosystem // "-"):\(.name // "-")"
			    ]
			| unique
		    | join("; ")
	  ) as $ecosystem_name

    # PURLを1脆弱性1行にまとめる
    | (
	[
		$v.affected[]?.package?.purl?
		    | select(type == "string" and length > 0)
		    ]
		| unique
	    | join("; ")
      ) as $purls

    # top-levelおよびaffected内のカスタム項目からCPEを抽出
    | (
	cpe_strings([
		$v.database_specific?,
		    $v.ecosystem_specific?,
			($v.affected[]?.database_specific?),
			($v.affected[]?.ecosystem_specific?)
		])
	| join("; ")
      ) as $cpes

    # aliasesにはCVE-ID、GHSA-IDなどが入る
    | (
	[
		$v.aliases[]?
		    | select(type == "string" and length > 0)
		    ]
		| unique
	    | join("; ")
      ) as $aliases

    | [
	($v.id // ""),
	    ($v.summary // ""),
	    $ecosystem_name,
	$purls,
	$cpes,
	$aliases
      ]
    | @tsv
### EOF ###
