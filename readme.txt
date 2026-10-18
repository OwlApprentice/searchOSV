about:
	OSV脆弱性データからCPEやPURLを検索ツールするためのツール
	OSV脆弱性データは https://storage.googleapis.com/osv-vulnerabilities/all.zip を使用

usage:
	検索用データの準備
		searchOSV.sh --download
			OSVからの脆弱性情報ダウンロードと検索インデックスの作成

	検索
		searchOSV.sh  キーワード

	複数キーワードでの検索
		searchOSV.sh  キーワード  |  grep  '二つ目のキーワード'

note:
	スクリプトが置かれたディレクトリに /data.searchOSV/ が作成され、
	その中に大容量(数GB)のOSV脆弱性データが保存されます。


[EOF]

