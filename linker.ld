ENTRY(_start)

SECTIONS
{
    . = 0x80000000;
    .boot :  {
        KEEP(*(boot.start))
        *(.boot .boot.*)
    }

    .text : {
        *(.text .text.*)
    }

    .rodata : { 
        . = ALIGN(16);
        *(.rodata .rodata.*) 
    }

    .data : { 
        . = ALIGN(16);
        *(.data .data.*) 
    }

    .bss : {
        . = ALIGN(16);
        PROVIDE(bss_start = .);
        *(.bss .bss.*)
        *(COMMON)
        PROVIDE(bss_end = .);
    }

    /* Define the stack location */
    . = ALIGN(16);
    PROVIDE(stack_bottom = .);
    . += 0x4000; /* 16KB for the boot stack */
    PROVIDE(stack_top = .);
}
