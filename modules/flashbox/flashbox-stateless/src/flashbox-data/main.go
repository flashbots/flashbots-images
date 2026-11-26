package main

import (
	"encoding/binary"
	"fmt"
	"log"
	"math"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/PowerDNS/lmdb-go/lmdb"
	"github.com/tidwall/redcon"
)

var env *lmdb.Env
var s, z lmdb.DBI

// Convert redis sorting score to LMDB key byte prefix matching sort order
func scoreToOrder(s []byte) ([]byte, error) {
	f, err := strconv.ParseFloat(string(s), 64)
	b := math.Float64bits(f)
	if math.Signbit(f) {
		b = ^b
	} else {
		b |= 1 << 63
	}
	return binary.BigEndian.AppendUint64(nil, b), err
}

func get(tx *lmdb.Txn, d lmdb.DBI, k []byte) any {
	v, err := tx.Get(d, k)
	if lmdb.IsNotFound(err) {
		return nil
	}
	if err != nil {
		return err
	}
	return append([]byte{}, v...)
}

func put(tx *lmdb.Txn, d lmdb.DBI, k, v []byte, ok any) any {
	if err := tx.Put(d, k, v, 0); err != nil {
		return err
	}
	return ok
}

func del(tx *lmdb.Txn, d lmdb.DBI, k []byte) any {
	switch err := tx.Del(d, k, nil); {
	case lmdb.IsNotFound(err):
		return redcon.SimpleInt(0)
	case err != nil:
		return err
	}
	return redcon.SimpleInt(1)
}

func exec(tx *lmdb.Txn, a [][]byte) any {
	switch cmd, n := strings.ToUpper(string(a[0])), len(a); {
	case cmd == "PING":
		return redcon.SimpleString("PONG")
	case cmd == "SET" && n == 3:
		return put(tx, s, a[1], a[2], redcon.SimpleString("OK"))
	case cmd == "GET" && n == 2:
		return get(tx, s, a[1])
	case cmd == "DEL" && n == 2:
		return del(tx, s, a[1])
	case cmd == "ZADD" && n == 4:
		sc, err := scoreToOrder(a[2])
		if err != nil {
			return err
		}
		return put(tx, z, a[1], append(sc, a[3]...), redcon.SimpleInt(1))
	}
	return fmt.Errorf("unknown command '%s'", a[0])
}

func handle(conn redcon.Conn, cmd redcon.Command) {
	queued, _ := conn.Context().([]redcon.Command)
	multi := false
	switch strings.ToUpper(string(cmd.Args[0])) {
	case "MULTI":
		conn.SetContext([]redcon.Command{})
		conn.WriteString("OK")
		return
	case "DISCARD":
		conn.SetContext(nil)
		conn.WriteString("OK")
		return
	case "EXEC":
		if queued == nil {
			conn.WriteError("ERR EXEC without MULTI")
			return
		}
		conn.SetContext(nil)
		multi = true
	default:
		if queued != nil {
			conn.SetContext(append(queued, cmd))
			conn.WriteString("QUEUED")
			return
		}
		queued = []redcon.Command{cmd}
	}
	var replies []any // written only after the txn committed
	if err := env.Update(func(tx *lmdb.Txn) error {
		for _, c := range queued {
			replies = append(replies, exec(tx, c.Args))
		}
		return nil
	}); err != nil {
		conn.WriteError("ERR " + err.Error())
		return
	}
	if multi {
		conn.WriteArray(len(replies))
	}
	for _, r := range replies {
		conn.WriteAny(r)
	}
}

// Only reuse pages afer specified duration
func pinSnapshots(period time.Duration) {
	var prev, cur *lmdb.Txn
	for {
		tx, _ := env.BeginTxn(nil, lmdb.Readonly)
		if prev != nil {
			prev.Abort()
		}
		prev, cur = cur, tx
		time.Sleep(period)
	}
}

func main() { // flashbox-data DIR ADDR [PIN_SECS]
	env, _ = lmdb.NewEnv()
	env.SetMapSize(1 << 40)
	env.SetMaxDBs(2)
	if err := env.Open(os.Args[1], lmdb.NoSync|lmdb.NoMetaSync, 0644); err != nil {
		log.Fatal(err)
	}
	if err := env.Update(func(tx *lmdb.Txn) (err error) {
		if s, err = tx.OpenDBI("s", lmdb.Create); err != nil {
			return
		}
		z, err = tx.OpenDBI("z", lmdb.Create|lmdb.DupSort)
		return
	}); err != nil {
		log.Fatal(err)
	}
	pin := 60
	if len(os.Args) > 3 {
		pin, _ = strconv.Atoi(os.Args[3])
	}
	go pinSnapshots(time.Duration(pin) * time.Second)
	log.Fatal(redcon.ListenAndServe(os.Args[2], handle, nil, nil))
}
