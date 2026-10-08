import hashlib,pathlib
path=pathlib.Path('Sources/SNDeliveryQueue.m')
s=path.read_text()
s=s.replace('- (void)clearWithCompletion:(void (^)(NSArray *))completion {','- (void)clearWithCompletion:(void (^)(NSArray<NSString *> *))completion {',1)
s=s.replace('   rc5 invalidated its old token on every arrival, allowing steady bursts to\n   debounce delivery forever. All state here belongs to lane. */','   rc5 invalidated its old token on every arrival. Coalescing prevents needless\n   cancellation during bursts. All state here belongs to lane. */',1)
path.write_text(s)
path=pathlib.Path('tests/TestDeliveryQueue.m')
path.write_text(path.read_text().replace('[q clearWithCompletion:^(__unused NSArray *r)','[q clearWithCompletion:^(__unused NSArray<NSString *> *r)',1))
path=pathlib.Path('Tweak.m')
s=path.read_text().replace('[contentDelivery clearWithCompletion:^(NSArray *identifiers)','[contentDelivery clearWithCompletion:^(NSArray<NSString *> *identifiers)',1)
needle='static void submitContent(NSDictionary *event,NSString *rid,void (^completion)(NSError *)) {\n    dispatch_async(worker,^{\n'
assert s.count(needle)==1
s=s.replace(needle,needle+'        @try {\n',1)
needle='        }];\n    });\n}\nstatic void startContentDelivery(void)'
assert s.count(needle)==1
s=s.replace(needle,'        }];\n        }@catch(NSException *e){\n            logLine(@"OUTBOX-SUBMIT-EXCEPTION name=%@",e.name);\n            completion([NSError errorWithDomain:@"SnapNotifySubmit" code:1 userInfo:nil]);\n        }\n    });\n}\nstatic void startContentDelivery(void)',1)
path.write_text(s)
expected={'Sources/SNDeliveryQueue.m': '329b2dc2c83d64c0e3ae8a03afc165f97c06463c733a8cc4fcd3dd5901d71b19', 'tests/TestDeliveryQueue.m': '546b631b1a660d7d3bef7876b7f081a2f4a756834634dcf3122b930c198aa584', 'Tweak.m': '68af950cdf91116b74a5f768ea3c8a27084111b6d1ded7980c35d2b72bcacf23'}
for name,wanted in expected.items():
    assert hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest()==wanted,name
