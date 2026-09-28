package com.naji.najimessenger

import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.util.Log

class BadgeHostApduService : HostApduService() {

    companion object {
        private const val TAG = "BadgeHCE"
        // Custom badge AID (8 bytes, legacy).
        val BADGE_AID = byteArrayOf(
            0xD2.toByte(), 0x76.toByte(), 0x00.toByte(), 0x00.toByte(),
            0x85.toByte(), 0x01.toByte(), 0x01.toByte(), 0x00.toByte()
        )
        // Standard NFC Forum NDEF Tag Application AID (7 bytes).
        // Every Type 4 reader selects this first.
        val NDEF_APP_AID = byteArrayOf(
            0xD2.toByte(), 0x76.toByte(), 0x00.toByte(), 0x00.toByte(),
            0x85.toByte(), 0x01.toByte(), 0x01.toByte()
        )
        private const val CLA = 0x00
        private const val INS_SELECT = 0xA4
        private const val INS_READ_BINARY = 0xB0

        private const val FILE_NONE = 0
        private const val FILE_CC = 1
        private const val FILE_NDEF = 2

        @Volatile
        private var ndefMessage: NdefMessage? = null

        fun setBadgeData(data: ByteArray) {
            val record = NdefRecord(
                NdefRecord.TNF_MIME_MEDIA,
                "application/vnd.najime.badge".toByteArray(),
                byteArrayOf(),
                data
            )
            ndefMessage = NdefMessage(arrayOf(record))
            Log.d(TAG, "Badge data set, ${data.size} bytes")
        }

        fun clearBadgeData() {
            ndefMessage = null
            Log.d(TAG, "Badge data cleared")
        }
    }

    private var selectedFileId = FILE_NONE

    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        if (commandApdu.size < 4) {
            return buildStatus(0x6700)
        }

        val cla = commandApdu[0].toInt() and 0xFF
        val ins = commandApdu[1].toInt() and 0xFF
        val p1 = commandApdu[2].toInt() and 0xFF
        val p2 = commandApdu[3].toInt() and 0xFF

        if (cla != CLA) {
            return buildStatus(0x6E00)
        }

        return when (ins) {
            INS_SELECT -> handleSelect(commandApdu, p1, p2)
            INS_READ_BINARY -> handleRead(commandApdu, p1, p2)
            else -> {
                Log.d(TAG, "Unsupported INS: 0x${ins.toString(16)}")
                buildStatus(0x6D00)
            }
        }
    }

    private fun handleSelect(apdu: ByteArray, p1: Int, p2: Int): ByteArray {
        // SELECT by File ID: 00 A4 00 0C 02 <fileIdHi> <fileIdLo>
        if (p1 == 0x00 && p2 == 0x0C) {
            if (apdu.size < 7) return buildStatus(0x6700)
            val lc = apdu[4].toInt() and 0xFF
            if (lc < 2 || apdu.size < 5 + lc) return buildStatus(0x6700)
            val fidHi = apdu[5].toInt() and 0xFF
            val fidLo = apdu[6].toInt() and 0xFF
            val fid = (fidHi shl 8) or fidLo
            return when (fid) {
                0xE103 -> {
                    selectedFileId = FILE_CC
                    Log.d(TAG, "CC file (E103) selected")
                    buildStatus(0x9000)
                }
                0x0001, 0xE104 -> {
                    selectedFileId = FILE_NDEF
                    Log.d(TAG, "NDEF file (${"%04X".format(fid)}) selected")
                    buildStatus(0x9000)
                }
                else -> {
                    Log.d(TAG, "Unknown File ID: ${"%04X".format(fid)}")
                    buildStatus(0x6A82)
                }
            }
        }

        // SELECT by Name (AID): 00 A4 04 00 <Lc> <AID> [Le=00]
        if (p1 == 0x04 && p2 == 0x00) {
            if (apdu.size < 5) return buildStatus(0x6700)
            val aidLen = apdu[4].toInt() and 0xFF
            if (aidLen > apdu.size - 5) return buildStatus(0x6700)
            val aid = apdu.copyOfRange(5, 5 + aidLen)

            if (aid.contentEquals(NDEF_APP_AID)) {
                Log.d(TAG, "NDEF Tag Application selected")
                // Default to CC after app select; reader will select files explicitly.
                selectedFileId = FILE_CC
                return buildStatus(0x9000)
            }
            if (aid.contentEquals(BADGE_AID)) {
                Log.d(TAG, "Badge AID selected (legacy)")
                selectedFileId = FILE_NDEF
                return buildStatus(0x9000)
            }
            Log.d(TAG, "Unknown AID: ${aid.joinToString("") { "%02X".format(it) }}")
            return buildStatus(0x6A82)
        }

        Log.d(TAG, "Unsupported SELECT P1=${"%02X".format(p1)} P2=${"%02X".format(p2)}")
        return buildStatus(0x6A82)
    }

    private fun handleRead(apdu: ByteArray, p1: Int, p2: Int): ByteArray {
        val msg = ndefMessage
        if (msg == null) {
            Log.d(TAG, "No badge data")
            return buildStatus(0x6A82)
        }

        val offset = (p1 shl 8) or p2
        // Short APDU: 00 B0 offHi offLo Le. Le==0 means 256. No Le (size==4) -> read to end.
        val le: Int = when {
            apdu.size > 4 -> {
                val raw = apdu[4].toInt() and 0xFF
                if (raw == 0) 256 else raw
            }
            else -> 256
        }

        val ndefBytes = msg.toByteArray()
        val ccFile = buildCCFile(ndefBytes.size + 2)
        val ndefFileSize = ndefBytes.size + 2
        val ndefFile = ByteArray(ndefFileSize)
        ndefFile[0] = ((ndefBytes.size shr 8) and 0xFF).toByte()
        ndefFile[1] = (ndefBytes.size and 0xFF).toByte()
        System.arraycopy(ndefBytes, 0, ndefFile, 2, ndefBytes.size)

        // CC and NDEF are separate files in Type 4, offsets restart per file.
        val fileData: ByteArray
        val fileName: String
        when (selectedFileId) {
            FILE_CC -> {
                fileData = ccFile
                fileName = "CC"
            }
            FILE_NDEF -> {
                fileData = ndefFile
                fileName = "NDEF"
            }
            else -> {
                // Be lenient: some readers READ without explicit file select
                // after app select. Default to CC at offset 0, NDEF otherwise
                // can't be guessed — require file select.
                Log.d(TAG, "READ without file select offset=$offset")
                return buildStatus(0x6A82)
            }
        }

        if (offset >= fileData.size) {
            return buildStatus(0x6A82)
        }

        val end = minOf(offset + le, fileData.size)
        val chunk = fileData.copyOfRange(offset, end)

        Log.d(TAG, "Read $fileName offset=$offset len=${chunk.size} total=${fileData.size}")
        return chunk + byteArrayOf(0x90.toByte(), 0x00)
    }

    private fun buildCCFile(ndefFileSize: Int): ByteArray {
        // NFC Forum Type 4 Tag CC file (File ID 0xE103):
        //   00 0F       CC data length = 15
        //   20          Mapping version 2.0
        //   04 06       MLe = 1030 (max R-APDU data size)
        //   04 00       MLc = 1024 (max C-APDU data size)
        //   04 06       NDEF File Control TLV: tag=0x04, len=6
        //     00 01       File ID
        //     FF FE       Max NDEF file size = 65534
        //     00          Read access: free
        //     00          Write access: free
        val maxNdefSize = minOf(65534, maxOf(ndefFileSize, 256))
        return byteArrayOf(
            0x00, 0x0F,
            0x20,
            0x04, 0x06,
            0x04, 0x00,
            0x04, 0x06,
            0x00, 0x01,
            ((maxNdefSize shr 8) and 0xFF).toByte(),
            (maxNdefSize and 0xFF).toByte(),
            0x00,
            0x00
        )
    }

    private fun buildStatus(sw: Int): ByteArray {
        return byteArrayOf(((sw shr 8) and 0xFF).toByte(), (sw and 0xFF).toByte())
    }

    override fun onDeactivated(reason: Int) {
        Log.d(TAG, "HCE deactivated: reason=$reason")
        // Keep selected file for next session? Reset to NONE to force clean select.
        selectedFileId = FILE_NONE
    }
}
