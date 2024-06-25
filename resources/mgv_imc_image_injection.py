from argparse import ArgumentParser
import math
import os

def read_field(file_path, offset, size, endian='little'):
    with open(file_path, 'rb') as file:
        file.seek(offset)
        data = file.read(size)
        data_int = int.from_bytes(data, endian)
    return data_int

def WORDS_TO_BYTES(address):
    return address * 2

def params_parser() -> ArgumentParser:
    parser = ArgumentParser()
    parser.add_argument("-nvm", "--nvm", help="MGV NVM image", type=str, default="", required=True)
    parser.add_argument("-z", "--zephyr", help="new Zephyr image to replace zephyr binary  ", type=str, default="", required=True)
    parser.add_argument("-o", "--output", help="path to output nvm file", type=str, default="", required=True)
    return parser


def main(args):
    image_path = args.nvm 
    injection_script_path = args.zephyr 

    # Specify the addresses and offsets
    UBOOT_high_ptr_words = 0x000038EA   # can be found in nvm-image_10003_fields.csv: Init_Module_,UBOOT_Pointer_L,Pointer_L
    UBOOT_low_ptr_words = 0x000038E9  # 
    
    UBOOT_high_ptr_address = WORDS_TO_BYTES(UBOOT_high_ptr_words)  # pointer is in words, we need byte offset
    UBOOT_low_ptr_address = WORDS_TO_BYTES(UBOOT_low_ptr_words)  # pointer is in words, we need byte offset

    
    inner_nvm_section_offset = (0x3800)      # active_bank_addr 

    # Read pointer values
    UBOOT_high = read_field(image_path, UBOOT_high_ptr_address, 2) 
    UBOOT_low = read_field(image_path, UBOOT_low_ptr_address, 2)

    # Calculate the final pointer address
    UBOOT_pointer_address = WORDS_TO_BYTES((UBOOT_high << 16) + UBOOT_low + inner_nvm_section_offset)

    print('UBOOT pointer: ', hex(UBOOT_pointer_address))
    # Read size from the final pointer address
    size = WORDS_TO_BYTES(read_field(image_path, UBOOT_pointer_address, 4))
    print('BL31 size: ', hex(size))
    u_boot_pointer_address = UBOOT_pointer_address + size +  4 + 4
    print('u-boot address: ', hex(u_boot_pointer_address))
    
    # u-boot image contains (temporary workaround): 
    # <bl3 size: 2 WORDs> <bl3 data> <zephyr size: 2 WORDs> <zephyr data>
    
    bl3_size = WORDS_TO_BYTES(read_field(image_path, u_boot_pointer_address, 4))
    zephyr_size_pointer = u_boot_pointer_address + 4 + bl3_size
    zephyr_size = WORDS_TO_BYTES(read_field(image_path, zephyr_size_pointer, 4))
        
    # Check if the size exceeds current zephyr limit
    # injection_size = os.path.getsize(injection_script_path)
    # if injection_size > zephyr_size:
    #     print(f"Error: Injection file size ({injection_size} bytes) exceeds current zephyr image size ({zephyr_size} bytes). Aborting .")
    #     exit(1)
    
    zephyr_actual_offset = zephyr_size_pointer + 4
    print('zephyr_actual_offset address: ', hex(zephyr_actual_offset))
    
    # write_injection(image_path, zephyr_actual_offset ,injection_script_path, args.output )
    with open(injection_script_path, 'rb') as injection_file:
        injection_data = injection_file.read()

    with open(args.output, 'wb') as new_file:
        with open(image_path, 'rb') as original_file:
            new_file.write(original_file.read(zephyr_size_pointer))
            new_file.write(math.ceil(len(injection_data)/2).to_bytes(4,byteorder='little'))
            new_file.write(injection_data)
            original_file.seek(zephyr_actual_offset + len(injection_data))
            new_file.write(original_file.read())


if __name__ == "__main__":
    args = params_parser().parse_args()    

    main(args)
