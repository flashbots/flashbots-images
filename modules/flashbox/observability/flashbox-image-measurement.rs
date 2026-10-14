// Print the UKI authenticode hash from the CCEL as a prometheus metric
use std::{env, fs, process::exit};

fn le32(b: &[u8]) -> usize { u32::from_le_bytes(b.try_into().unwrap()) as usize }

fn main() {
    let path = env::args().nth(1).unwrap_or("/sys/firmware/acpi/tables/data/CCEL".into());
    let log = fs::read(&path).unwrap_or_else(|e| { eprintln!("{path}: {e}"); exit(1) });
    // skip the header event
    let mut p = 32 + log.get(28..32).map_or(0, le32);
    // mr, type, ndigests, alg, sha384, len, data
    while let Some(ev) = log.get(p..p + 66) {
        if le32(&ev[..4]) == 2 && le32(&ev[4..8]) == 0x8000_0003 { // RTMR1, EV_EFI_BOOT_SERVICES_APPLICATION
            let hash: String = ev[14..62].iter().map(|b| format!("{b:02x}")).collect();
            print!("# HELP flashbox_image_measurement Measurement of the booted image.\n\
                    # TYPE flashbox_image_measurement gauge\n\
                    flashbox_image_measurement{{uki_authenticode=\"{hash}\"}} 1\n");
            return;
        }
        p += 66 + le32(&ev[62..]);
    }
    eprintln!("{path}: UKI measurement not found");
    exit(1);
}
