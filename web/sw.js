function _M0TP411moonbitlang5async8internal9coroutine9Scheduler(param0, param1, param2, param3) {
  this.coro_id = param0;
  this.curr_coro = param1;
  this.run_later = param2;
  this.all_coros = param3;
}
function _M0TPB9ArrayViewGRP411moonbitlang5async8internal9coroutine9CoroutineE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0DTPC16option6OptionGRP311moonbitlang5async9js__async7PromiseGOsEE4None() {}
_M0DTPC16option6OptionGRP311moonbitlang5async9js__async7PromiseGOsEE4None.prototype.$tag = 0;
const _M0DTPC16option6OptionGRP311moonbitlang5async9js__async7PromiseGOsEE4None__ = new _M0DTPC16option6OptionGRP311moonbitlang5async9js__async7PromiseGOsEE4None();
function _M0DTPC16option6OptionGRP311moonbitlang5async9js__async7PromiseGOsEE4Some(param0) {
  this._0 = param0;
}
_M0DTPC16option6OptionGRP311moonbitlang5async9js__async7PromiseGOsEE4Some.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw64_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__assetL5State8State__0(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw64_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__assetL5State8State__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw64_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__assetL5State12_2atry_2f263(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP46f4ah6o3dsh7browser2sw64_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__assetL5State12_2atry_2f263.prototype.$tag = 1;
function $oob() {
  throw new Error("Index out of bounds");
}
class $PanicError extends Error {}
function $panic() {
  throw new $PanicError();
}
function _M0TPB13StringBuilder(param0) {
  this.val = param0;
}
function _M0TPC16string10StringView(param0, param1, param2) {
  this.str = param0;
  this.start = param1;
  this.end = param2;
}
const _M0FPB12random__seed = () => {
  if (globalThis.crypto?.getRandomValues) {
    const array = new Uint32Array(1);
    globalThis.crypto.getRandomValues(array);
    return array[0] | 0; // Convert to signed 32
  } else {
    return Math.floor(Math.random() * 0x100000000) | 0; // Fallback to Math.random
  }
};
function _M0TPB6Hasher(param0) {
  this.acc = param0;
}
const _M0FPB19int__to__string__js = (x, radix) => {
  return x.toString(radix);
};
function _M0TPB4IterGRP411moonbitlang5async8internal9coroutine9CoroutineE(param0, param1) {
  this.f = param0;
  this.size_hint = param1;
}
function _M0TPB4IterGcE(param0, param1) {
  this.f = param0;
  this.size_hint = param1;
}
function _M0TPB8MutLocalGiE(param0) {
  this.val = param0;
}
function $make_array_len_and_init(a, b) {
  const arr = new Array(a);
  arr.fill(b);
  return arr;
}
const _M0MPB7JSArray4push = (arr, val) => { arr.push(val); };
function _M0TPB4IterGRPC16string10StringViewE(param0, param1) {
  this.f = param0;
  this.size_hint = param1;
}
function _M0TPB8MutLocalGORPC16string10StringViewE(param0) {
  this.val = param0;
}
function _M0TPB9ArrayViewGsE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPC13ref3RefGiE(param0) {
  this.val = param0;
}
function _M0TPC13ref3RefGORP311moonbitlang5async9js__async7PromiseGOsEE(param0) {
  this.val = param0;
}
function _M0TPC13set3SetGRP411moonbitlang5async8internal9coroutine9CoroutineE(param0, param1, param2, param3, param4, param5, param6) {
  this.entries = param0;
  this.size = param1;
  this.capacity = param2;
  this.capacity_mask = param3;
  this.grow_at = param4;
  this.head = param5;
  this.tail = param6;
}
function _M0TPC13set5EntryGRP411moonbitlang5async8internal9coroutine9CoroutineE(param0, param1, param2, param3, param4) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
}
function _M0TPB8MutLocalGORPC13set5EntryGRP411moonbitlang5async8internal9coroutine9CoroutineEE(param0) {
  this.val = param0;
}
function _M0TPC15deque5DequeGRP411moonbitlang5async8internal9coroutine9CoroutineE(param0, param1, param2) {
  this.buf = param0;
  this.len = param1;
  this.head = param2;
}
function _M0DTP411moonbitlang5async8internal9coroutine5State4Done() {}
_M0DTP411moonbitlang5async8internal9coroutine5State4Done.prototype.$tag = 0;
const _M0DTP411moonbitlang5async8internal9coroutine5State4Done__ = new _M0DTP411moonbitlang5async8internal9coroutine5State4Done();
function _M0DTP411moonbitlang5async8internal9coroutine5State4Fail(param0) {
  this._0 = param0;
}
_M0DTP411moonbitlang5async8internal9coroutine5State4Fail.prototype.$tag = 1;
function _M0DTP411moonbitlang5async8internal9coroutine5State9Cancelled() {}
_M0DTP411moonbitlang5async8internal9coroutine5State9Cancelled.prototype.$tag = 2;
const _M0DTP411moonbitlang5async8internal9coroutine5State9Cancelled__ = new _M0DTP411moonbitlang5async8internal9coroutine5State9Cancelled();
function _M0DTP411moonbitlang5async8internal9coroutine5State7Running() {}
_M0DTP411moonbitlang5async8internal9coroutine5State7Running.prototype.$tag = 3;
const _M0DTP411moonbitlang5async8internal9coroutine5State7Running__ = new _M0DTP411moonbitlang5async8internal9coroutine5State7Running();
function _M0DTP411moonbitlang5async8internal9coroutine5State7Suspend(param0) {
  this._0 = param0;
}
_M0DTP411moonbitlang5async8internal9coroutine5State7Suspend.prototype.$tag = 4;
function _M0DTPC16result6ResultGORP411moonbitlang5async8internal9coroutine13SuspendResultRPB9CancelledE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGORP411moonbitlang5async8internal9coroutine13SuspendResultRPB9CancelledE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGORP411moonbitlang5async8internal9coroutine13SuspendResultRPB9CancelledE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGORP411moonbitlang5async8internal9coroutine13SuspendResultRPB9CancelledE2Ok.prototype.$tag = 1;
function _M0DTPC16result6ResultGOuRPB9CancelledE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOuRPB9CancelledE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGOuRPB9CancelledE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOuRPB9CancelledE2Ok.prototype.$tag = 1;
function _M0DTPC15error5Error59f4ah6o_2fdsh_2fbrowser_2fsw_2eWorkerFailure_2eWorkerFailure(param0) {
  this._0 = param0;
}
_M0DTPC15error5Error59f4ah6o_2fdsh_2fbrowser_2fsw_2eWorkerFailure_2eWorkerFailure.prototype.$tag = 2;
function _M0DTPC15error5Error52moonbitlang_2fcore_2fbuiltin_2eCancelled_2eCancelled() {}
_M0DTPC15error5Error52moonbitlang_2fcore_2fbuiltin_2eCancelled_2eCancelled.prototype.$tag = 1;
const _M0DTPC15error5Error52moonbitlang_2fcore_2fbuiltin_2eCancelled_2eCancelled__ = new _M0DTPC15error5Error52moonbitlang_2fcore_2fbuiltin_2eCancelled_2eCancelled();
function _M0DTPC15error5Error51moonbitlang_2fasync_2fjs__async_2eJsError_2eJsError(param0) {
  this._0 = param0;
}
_M0DTPC15error5Error51moonbitlang_2fasync_2fjs__async_2eJsError_2eJsError.prototype.$tag = 0;
function _M0DTP411moonbitlang5async8internal9coroutine55_24moonbitlang_2fasync_2finternal_2fcoroutine_2esuspendL5State8State__0(param0) {
  this._0 = param0;
}
_M0DTP411moonbitlang5async8internal9coroutine55_24moonbitlang_2fasync_2finternal_2fcoroutine_2esuspendL5State8State__0.prototype.$tag = 0;
function _M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State8State__0(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State8State__0.prototype.$tag = 0;
function _M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State11_2atry_2f93(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State11_2atry_2f93.prototype.$tag = 1;
function _M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State8State__2(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State8State__2.prototype.$tag = 2;
function _M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State29_2acancellation__handler_2f96(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State29_2acancellation__handler_2f96.prototype.$tag = 3;
function _M0TP411moonbitlang5async8internal9coroutine9Coroutine(param0, param1, param2, param3, param4, param5, param6) {
  this.coro_id = param0;
  this.state = param1;
  this.shielded = param2;
  this.cancelled = param3;
  this.ready = param4;
  this.downstream = param5;
  this.loc = param6;
}
function _M0DTPC16result6ResultGOuRPC15error5ErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOuRPC15error5ErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok.prototype.$tag = 1;
function _M0DTP411moonbitlang5async8internal9coroutine69_24moonbitlang_2fasync_2finternal_2fcoroutine_2eprotect__from__cancelL5StateGuE30_2acancellation__handler_2f162(param0) {
  this._0 = param0;
}
_M0DTP411moonbitlang5async8internal9coroutine69_24moonbitlang_2fasync_2finternal_2fcoroutine_2eprotect__from__cancelL5StateGuE30_2acancellation__handler_2f162.prototype.$tag = 0;
function _M0DTP411moonbitlang5async8internal9coroutine69_24moonbitlang_2fasync_2finternal_2fcoroutine_2eprotect__from__cancelL5StateGuE19_2adefer__try_2f157(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP411moonbitlang5async8internal9coroutine69_24moonbitlang_2fasync_2finternal_2fcoroutine_2eprotect__from__cancelL5StateGuE19_2adefer__try_2f157.prototype.$tag = 1;
function _M0DTP411moonbitlang5async8internal9coroutine69_24moonbitlang_2fasync_2finternal_2fcoroutine_2eprotect__from__cancelL5StateGuE8State__2(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP411moonbitlang5async8internal9coroutine69_24moonbitlang_2fasync_2finternal_2fcoroutine_2eprotect__from__cancelL5StateGuE8State__2.prototype.$tag = 2;
function _M0DTPC16result6ResultGOOuRPC15error5ErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOOuRPC15error5ErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGOOuRPC15error5ErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOOuRPC15error5ErrorE2Ok.prototype.$tag = 1;
function _M0DTPC16option6OptionGOuE4None() {}
_M0DTPC16option6OptionGOuE4None.prototype.$tag = 0;
const _M0DTPC16option6OptionGOuE4None__ = new _M0DTPC16option6OptionGOuE4None();
function _M0DTPC16option6OptionGOuE4Some(param0) {
  this._0 = param0;
}
_M0DTPC16option6OptionGOuE4Some.prototype.$tag = 1;
function _M0DTPC16result6ResultGOORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGOORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok.prototype.$tag = 1;
function _M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4None() {}
_M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4None.prototype.$tag = 0;
const _M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4None__ = new _M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4None();
function _M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4Some(param0) {
  this._0 = param0;
}
_M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4Some.prototype.$tag = 1;
function _M0DTPC16result6ResultGOOOsRPC15error5ErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOOOsRPC15error5ErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGOOOsRPC15error5ErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOOOsRPC15error5ErrorE2Ok.prototype.$tag = 1;
function _M0DTPC16option6OptionGOsE4None() {}
_M0DTPC16option6OptionGOsE4None.prototype.$tag = 0;
const _M0DTPC16option6OptionGOsE4None__ = new _M0DTPC16option6OptionGOsE4None();
function _M0DTPC16option6OptionGOsE4Some(param0) {
  this._0 = param0;
}
_M0DTPC16option6OptionGOsE4Some.prototype.$tag = 1;
function _M0DTPC16result6ResultGOObRPC15error5ErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOObRPC15error5ErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGOObRPC15error5ErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOObRPC15error5ErrorE2Ok.prototype.$tag = 1;
function _M0DTPC16option6OptionGObE4None() {}
_M0DTPC16option6OptionGObE4None.prototype.$tag = 0;
const _M0DTPC16option6OptionGObE4None__ = new _M0DTPC16option6OptionGObE4None();
function _M0DTPC16option6OptionGObE4Some(param0) {
  this._0 = param0;
}
_M0DTPC16option6OptionGObE4Some.prototype.$tag = 1;
function _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGuE30_2acancellation__handler_2f171(param0) {
  this._0 = param0;
}
_M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGuE30_2acancellation__handler_2f171.prototype.$tag = 0;
function _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGuE8State__1(param0) {
  this._0 = param0;
}
_M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGuE8State__1.prototype.$tag = 1;
function _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE30_2acancellation__handler_2f171(param0) {
  this._0 = param0;
}
_M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE30_2acancellation__handler_2f171.prototype.$tag = 0;
function _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE8State__1(param0) {
  this._0 = param0;
}
_M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE8State__1.prototype.$tag = 1;
function _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGbE30_2acancellation__handler_2f171(param0) {
  this._0 = param0;
}
_M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGbE30_2acancellation__handler_2f171.prototype.$tag = 0;
function _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGbE8State__1(param0) {
  this._0 = param0;
}
_M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGbE8State__1.prototype.$tag = 1;
const _M0FP411moonbitlang5async8internal11event__loop12set__timeout = (duration, f) => setTimeout(f, duration);
const _M0MP311moonbitlang5async9js__async15AbortController5abort = (controller) => controller.abort();
const _M0MP311moonbitlang5async9js__async7JsValue4then = (p, resolve, reject) => p.then(resolve, reject);
function _M0DTPC16result6ResultGObRPC15error5ErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGObRPC15error5ErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGObRPC15error5ErrorE2Ok.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE18_2adefer__try_2f90(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE18_2adefer__try_2f90.prototype.$tag = 0;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE8State__1(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE8State__1.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE18_2adefer__try_2f91(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE18_2adefer__try_2f91.prototype.$tag = 2;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE18_2adefer__try_2f90(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE18_2adefer__try_2f90.prototype.$tag = 0;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE8State__1(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE8State__1.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE18_2adefer__try_2f91(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE18_2adefer__try_2f91.prototype.$tag = 2;
function _M0DTPC16result6ResultGORPB5ArrayGsERPC15error5ErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGORPB5ArrayGsERPC15error5ErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGORPB5ArrayGsERPC15error5ErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGORPB5ArrayGsERPC15error5ErrorE2Ok.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE18_2adefer__try_2f90(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE18_2adefer__try_2f90.prototype.$tag = 0;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE8State__1(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE8State__1.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE18_2adefer__try_2f91(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE18_2adefer__try_2f91.prototype.$tag = 2;
function _M0DTPC16option6OptionGRPB5ArrayGsEE4None() {}
_M0DTPC16option6OptionGRPB5ArrayGsEE4None.prototype.$tag = 0;
const _M0DTPC16option6OptionGRPB5ArrayGsEE4None__ = new _M0DTPC16option6OptionGRPB5ArrayGsEE4None();
function _M0DTPC16option6OptionGRPB5ArrayGsEE4Some(param0) {
  this._0 = param0;
}
_M0DTPC16option6OptionGRPB5ArrayGsEE4Some.prototype.$tag = 1;
function _M0DTPC16result6ResultGOOsRPC15error5ErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOOsRPC15error5ErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGOsE18_2adefer__try_2f90(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGOsE18_2adefer__try_2f90.prototype.$tag = 0;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGOsE8State__1(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGOsE8State__1.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGOsE18_2adefer__try_2f91(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGOsE18_2adefer__try_2f91.prototype.$tag = 2;
function _M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw7SwCacheRPC15error5ErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw7SwCacheRPC15error5ErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw7SwCacheRPC15error5ErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw7SwCacheRPC15error5ErrorE2Ok.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw7SwCacheE18_2adefer__try_2f90(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw7SwCacheE18_2adefer__try_2f90.prototype.$tag = 0;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw7SwCacheE8State__1(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw7SwCacheE8State__1.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw7SwCacheE18_2adefer__try_2f91(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw7SwCacheE18_2adefer__try_2f91.prototype.$tag = 2;
function _M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw7SwCacheE4None() {}
_M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw7SwCacheE4None.prototype.$tag = 0;
function _M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw7SwCacheE4Some(param0) {
  this._0 = param0;
}
_M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw7SwCacheE4Some.prototype.$tag = 1;
function _M0DTPC16result6ResultGOsRPC15error5ErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOsRPC15error5ErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGOsRPC15error5ErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGOsRPC15error5ErrorE2Ok.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE18_2adefer__try_2f90(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE18_2adefer__try_2f90.prototype.$tag = 0;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE8State__1(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE8State__1.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE18_2adefer__try_2f91(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE18_2adefer__try_2f91.prototype.$tag = 2;
function _M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE18_2adefer__try_2f90(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE18_2adefer__try_2f90.prototype.$tag = 0;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE8State__1(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE8State__1.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE18_2adefer__try_2f91(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE18_2adefer__try_2f91.prototype.$tag = 2;
function _M0DTPC16result6ResultGORPB5ArrayGRP46f4ah6o3dsh7browser2sw8SwClientERPC15error5ErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGORPB5ArrayGRP46f4ah6o3dsh7browser2sw8SwClientERPC15error5ErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGORPB5ArrayGRP46f4ah6o3dsh7browser2sw8SwClientERPC15error5ErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGORPB5ArrayGRP46f4ah6o3dsh7browser2sw8SwClientERPC15error5ErrorE2Ok.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGRP46f4ah6o3dsh7browser2sw8SwClientEE18_2adefer__try_2f90(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGRP46f4ah6o3dsh7browser2sw8SwClientEE18_2adefer__try_2f90.prototype.$tag = 0;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGRP46f4ah6o3dsh7browser2sw8SwClientEE8State__1(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGRP46f4ah6o3dsh7browser2sw8SwClientEE8State__1.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGRP46f4ah6o3dsh7browser2sw8SwClientEE18_2adefer__try_2f91(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGRP46f4ah6o3dsh7browser2sw8SwClientEE18_2adefer__try_2f91.prototype.$tag = 2;
function _M0DTPC16option6OptionGRPB5ArrayGRP46f4ah6o3dsh7browser2sw8SwClientEE4None() {}
_M0DTPC16option6OptionGRPB5ArrayGRP46f4ah6o3dsh7browser2sw8SwClientEE4None.prototype.$tag = 0;
function _M0DTPC16option6OptionGRPB5ArrayGRP46f4ah6o3dsh7browser2sw8SwClientEE4Some(param0) {
  this._0 = param0;
}
_M0DTPC16option6OptionGRPB5ArrayGRP46f4ah6o3dsh7browser2sw8SwClientEE4Some.prototype.$tag = 1;
function _M0DTPC16result6ResultGORPB5ArrayGRP46f4ah6o3dsh7browser2sw9SwRequestERPC15error5ErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGORPB5ArrayGRP46f4ah6o3dsh7browser2sw9SwRequestERPC15error5ErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGORPB5ArrayGRP46f4ah6o3dsh7browser2sw9SwRequestERPC15error5ErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGORPB5ArrayGRP46f4ah6o3dsh7browser2sw9SwRequestERPC15error5ErrorE2Ok.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGRP46f4ah6o3dsh7browser2sw9SwRequestEE18_2adefer__try_2f90(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGRP46f4ah6o3dsh7browser2sw9SwRequestEE18_2adefer__try_2f90.prototype.$tag = 0;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGRP46f4ah6o3dsh7browser2sw9SwRequestEE8State__1(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGRP46f4ah6o3dsh7browser2sw9SwRequestEE8State__1.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGRP46f4ah6o3dsh7browser2sw9SwRequestEE18_2adefer__try_2f91(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGRP46f4ah6o3dsh7browser2sw9SwRequestEE18_2adefer__try_2f91.prototype.$tag = 2;
function _M0DTPC16option6OptionGRPB5ArrayGRP46f4ah6o3dsh7browser2sw9SwRequestEE4None() {}
_M0DTPC16option6OptionGRPB5ArrayGRP46f4ah6o3dsh7browser2sw9SwRequestEE4None.prototype.$tag = 0;
function _M0DTPC16option6OptionGRPB5ArrayGRP46f4ah6o3dsh7browser2sw9SwRequestEE4Some(param0) {
  this._0 = param0;
}
_M0DTPC16option6OptionGRPB5ArrayGRP46f4ah6o3dsh7browser2sw9SwRequestEE4Some.prototype.$tag = 1;
function _M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw7SwChunkRPC15error5ErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw7SwChunkRPC15error5ErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw7SwChunkRPC15error5ErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw7SwChunkRPC15error5ErrorE2Ok.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw7SwChunkE18_2adefer__try_2f90(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw7SwChunkE18_2adefer__try_2f90.prototype.$tag = 0;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw7SwChunkE8State__1(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw7SwChunkE8State__1.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw7SwChunkE18_2adefer__try_2f91(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRP46f4ah6o3dsh7browser2sw7SwChunkE18_2adefer__try_2f91.prototype.$tag = 2;
function _M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw7SwChunkE4None() {}
_M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw7SwChunkE4None.prototype.$tag = 0;
function _M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw7SwChunkE4Some(param0) {
  this._0 = param0;
}
_M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw7SwChunkE4Some.prototype.$tag = 1;
function _M0TP311moonbitlang5async9js__async13PromiseWaiterGbE(param0, param1, param2) {
  this.coro = param0;
  this.ret = param1;
  this.err = param2;
}
function _M0TP311moonbitlang5async9js__async13PromiseWaiterGuE(param0, param1, param2) {
  this.coro = param0;
  this.ret = param1;
  this.err = param2;
}
function _M0TP311moonbitlang5async9js__async13PromiseWaiterGRPB5ArrayGsEE(param0, param1, param2) {
  this.coro = param0;
  this.ret = param1;
  this.err = param2;
}
function _M0TP311moonbitlang5async9js__async13PromiseWaiterGsE(param0, param1, param2) {
  this.coro = param0;
  this.ret = param1;
  this.err = param2;
}
const _M0MP311moonbitlang5async9js__async15AbortController3new = () => new AbortController();
const _M0MP311moonbitlang5async9js__async15AbortController6signal = (controller) => controller.signal;
const _M0MP311moonbitlang5async9js__async11AbortSignal7aborted = (signal) => signal.aborted;
const _M0MP311moonbitlang5async9js__async11AbortSignal9on__abort = (signal, f) => signal.addEventListener('abort', f, { once: true });
const _M0MP311moonbitlang5async9js__async11AbortSignal23remove__abort__listener = (signal, f) => signal.removeEventListener('abort', f);
const _M0MP311moonbitlang5async9js__async7JsValue12abort__error = () => {
   const err = new Error()
   err.name = 'AbortError'
   return err
 };
const _M0MP311moonbitlang5async9js__async7JsValue12new__promise = (f) => new Promise(f);
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE19_2adefer__try_2f133(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE19_2adefer__try_2f133.prototype.$tag = 0;
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE8State__1(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE8State__1.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE12_2atry_2f138(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE12_2atry_2f138.prototype.$tag = 2;
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE8State__3(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE8State__3.prototype.$tag = 3;
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE19_2adefer__try_2f133(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE19_2adefer__try_2f133.prototype.$tag = 0;
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE8State__1(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE8State__1.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE12_2atry_2f138(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE12_2atry_2f138.prototype.$tag = 2;
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE8State__3(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE8State__3.prototype.$tag = 3;
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGOsE19_2adefer__try_2f133(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGOsE19_2adefer__try_2f133.prototype.$tag = 0;
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGOsE8State__1(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGOsE8State__1.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGOsE12_2atry_2f138(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGOsE12_2atry_2f138.prototype.$tag = 2;
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGOsE8State__3(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGOsE8State__3.prototype.$tag = 3;
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE19_2adefer__try_2f133(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE19_2adefer__try_2f133.prototype.$tag = 0;
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE8State__1(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE8State__1.prototype.$tag = 1;
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE12_2atry_2f138(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE12_2atry_2f138.prototype.$tag = 2;
function _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE8State__3(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE8State__3.prototype.$tag = 3;
const _M0MP311moonbitlang5async9js__async7JsValue10to__string = (v) => v.toString();
const _M0FP46f4ah6o3dsh7browser2sw13sw__available = () => typeof self !== "undefined" && !!self.addEventListener && typeof caches !== "undefined";
const _M0FP46f4ah6o3dsh7browser2sw20sw__location__origin = () => self.location.origin;
const _M0FP46f4ah6o3dsh7browser2sw24sw__add__event__listener = (name, callback) => self.addEventListener(name, callback);
const _M0FP46f4ah6o3dsh7browser2sw17sw__skip__waiting = () => { void self.skipWaiting(); };
const _M0FP46f4ah6o3dsh7browser2sw22sw__event__wait__until = (event, promise) => event.waitUntil(promise);
const _M0FP46f4ah6o3dsh7browser2sw24sw__event__respond__with = (event, promise) => event.respondWith(promise);
const _M0FP46f4ah6o3dsh7browser2sw18sw__event__request = (event) => event.request;
const _M0FP46f4ah6o3dsh7browser2sw16sw__request__url = (request) => request.url;
const _M0FP46f4ah6o3dsh7browser2sw19sw__request__method = (request) => request.method;
const _M0FP46f4ah6o3dsh7browser2sw17sw__request__mode = (request) => request.mode;
const _M0FP46f4ah6o3dsh7browser2sw24sw__request__has__header = (request, name) => request.headers.has(name);
const _M0FP46f4ah6o3dsh7browser2sw21sw__event__client__id = (event) => event.clientId || "";
const _M0FP46f4ah6o3dsh7browser2sw32sw__event__resulting__client__id = (event) => event.resultingClientId || "";
const _M0FP46f4ah6o3dsh7browser2sw15sw__url__origin = (url) => new URL(url).origin;
const _M0FP46f4ah6o3dsh7browser2sw13sw__url__path = (url) => new URL(url).pathname;
const _M0FP46f4ah6o3dsh7browser2sw15sw__url__search = (url) => new URL(url).search;
const _M0FP46f4ah6o3dsh7browser2sw21sw__encode__component = (value) => encodeURIComponent(value);
const _M0FP46f4ah6o3dsh7browser2sw21sw__decode__component = (value) => { try { return decodeURIComponent(value); } catch { return ""; } };
const _M0FP46f4ah6o3dsh7browser2sw11sw__now__ms = () => String(Date.now());
const _M0FP46f4ah6o3dsh7browser2sw18sw__random__suffix = () => Math.random().toString(36).slice(2);
const _M0FP46f4ah6o3dsh7browser2sw15sw__cache__open = (name) => caches.open(name);
const _M0FP46f4ah6o3dsh7browser2sw16sw__cache__names = () => caches.keys();
const _M0FP46f4ah6o3dsh7browser2sw17sw__cache__delete = (name) => caches.delete(name);
const _M0FP46f4ah6o3dsh7browser2sw16sw__cache__match = (cache, key) => cache.match(key);
const _M0FP46f4ah6o3dsh7browser2sw14sw__cache__has = (cache, key) => cache.match(key).then((response) => !!response);
const _M0FP46f4ah6o3dsh7browser2sw14sw__cache__put = (cache, key, response) => cache.put(key, response);
const _M0FP46f4ah6o3dsh7browser2sw22sw__cache__delete__key = (cache, key) => cache.delete(key);
const _M0FP46f4ah6o3dsh7browser2sw15sw__cache__keys = (cache) => cache.keys();
const _M0FP46f4ah6o3dsh7browser2sw18sw__response__text = (response) => response.text();
const _M0FP46f4ah6o3dsh7browser2sw18sw__text__response = (value, contentType) => new Response(value, { headers: { "content-type": contentType } });
const _M0FP46f4ah6o3dsh7browser2sw32sw__text__response__with__status = (status, body, contentType) => new Response(body, { status, headers: { "content-type": contentType } });
const _M0FP46f4ah6o3dsh7browser2sw16sw__response__ok = (response) => response.ok;
const _M0FP46f4ah6o3dsh7browser2sw18sw__response__type = (response) => response.type;
const _M0FP46f4ah6o3dsh7browser2sw20sw__response__header = (response, name) => response.headers.get(name) || "";
const _M0FP46f4ah6o3dsh7browser2sw17sw__response__url = (response) => response.url || "";
const _M0FP46f4ah6o3dsh7browser2sw19sw__response__clone = (response) => response.clone();
const _M0FP46f4ah6o3dsh7browser2sw20sw__response__reader = (response) => response.body.getReader();
const _M0FP46f4ah6o3dsh7browser2sw23sw__response__has__body = (response) => !!response.body;
const _M0FP46f4ah6o3dsh7browser2sw16sw__reader__read = (reader) => reader.read();
const _M0FP46f4ah6o3dsh7browser2sw19sw__chunk__is__done = (chunk) => !!chunk.done;
const _M0FP46f4ah6o3dsh7browser2sw23sw__chunk__byte__length = (chunk) => chunk.value ? chunk.value.byteLength : 0;
const _M0FP46f4ah6o3dsh7browser2sw18sw__reader__cancel = (reader) => reader.cancel();
const _M0FP46f4ah6o3dsh7browser2sw19sw__reader__release = (reader) => reader.releaseLock();
const _M0FP46f4ah6o3dsh7browser2sw9sw__fetch = (url, requestMethod, cache, credentials, mode, signal) => fetch(url, { method: requestMethod, cache, credentials, mode, signal });
const _M0FP46f4ah6o3dsh7browser2sw17sw__with__timeout = (promise, timeoutMs, errorMessage, onTimeout) => new Promise((resolve, reject) => {
   const timer = setTimeout(() => { onTimeout(); reject(new Error(errorMessage)); }, timeoutMs);
   promise.then((value) => { clearTimeout(timer); resolve(value); }, (error) => { clearTimeout(timer); reject(error); });
 });
const _M0FP46f4ah6o3dsh7browser2sw23sw__clients__match__all = (clientType, includeUncontrolled) => self.clients.matchAll({ type: clientType, includeUncontrolled });
const _M0FP46f4ah6o3dsh7browser2sw14sw__client__id = (client) => client.id;
const _M0FP46f4ah6o3dsh7browser2sw18sw__clients__claim = () => self.clients.claim();
function _M0DTP46f4ah6o3dsh7browser2sw60_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecancel__shell__body__readerL5State8State__0(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw60_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecancel__shell__body__readerL5State8State__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw60_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecancel__shell__body__readerL5State12_2atry_2f233(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw60_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecancel__shell__body__readerL5State12_2atry_2f233.prototype.$tag = 1;
function _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None() {}
_M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None.prototype.$tag = 0;
const _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__ = new _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None();
function _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4Some(param0) {
  this._0 = param0;
}
_M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4Some.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State19_2adefer__try_2f246(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State19_2adefer__try_2f246.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__1(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__1.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State11_2awhile__2(param0, param1, param2, param3, param4) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
}
_M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State11_2awhile__2.prototype.$tag = 2;
function _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__3(param0, param1, param2, param3, param4, param5) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
}
_M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__3.prototype.$tag = 3;
function _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__4(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__4.prototype.$tag = 4;
function _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__5(param0, param1, param2, param3, param4, param5, param6) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
}
_M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__5.prototype.$tag = 5;
function _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__6(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__6.prototype.$tag = 6;
function _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State12_2atry_2f250(param0, param1, param2, param3, param4) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
}
_M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State12_2atry_2f250.prototype.$tag = 7;
function _M0DTP46f4ah6o3dsh7browser2sw85_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__generation__after__completion_2elambda_2f542L5State8State__0(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw85_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__generation__after__completion_2elambda_2f542L5State8State__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw85_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__generation__after__completion_2elambda_2f542L5State8State__1(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw85_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__generation__after__completion_2elambda_2f542L5State8State__1.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw85_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__generation__after__completion_2elambda_2f542L5State12_2atry_2f258(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw85_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__generation__after__completion_2elambda_2f542L5State12_2atry_2f258.prototype.$tag = 2;
function _M0DTPC16option6OptionGRP311moonbitlang5async9js__async11AbortSignalE4None() {}
_M0DTPC16option6OptionGRP311moonbitlang5async9js__async11AbortSignalE4None.prototype.$tag = 0;
const _M0DTPC16option6OptionGRP311moonbitlang5async9js__async11AbortSignalE4None__ = new _M0DTPC16option6OptionGRP311moonbitlang5async9js__async11AbortSignalE4None();
function _M0DTPC16option6OptionGRP311moonbitlang5async9js__async11AbortSignalE4Some(param0) {
  this._0 = param0;
}
_M0DTPC16option6OptionGRP311moonbitlang5async9js__async11AbortSignalE4Some.prototype.$tag = 1;
const _M0FP46f4ah6o3dsh7browser2sw17sw__make__request = (url, requestMethod, cacheMode, credentialsMode, requestMode) => new Request(url, { method: requestMethod, cache: cacheMode, credentials: credentialsMode, mode: requestMode });
function _M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State12_2atry_2f268(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State12_2atry_2f268.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State8State__1(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State8State__1.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State8State__2(param0, param1, param2, param3, param4, param5, param6) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
}
_M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State8State__2.prototype.$tag = 2;
function _M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State8State__3(param0, param1, param2, param3, param4, param5, param6, param7, param8) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
  this._7 = param7;
  this._8 = param8;
}
_M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State8State__3.prototype.$tag = 3;
function _M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State12_2atry_2f273(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State12_2atry_2f273.prototype.$tag = 4;
function _M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__0(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__1(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__1.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__2(param0, param1, param2, param3, param4) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
}
_M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__2.prototype.$tag = 2;
function _M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__3(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__3.prototype.$tag = 3;
function _M0DTP46f4ah6o3dsh7browser2sw48_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewrite__metadataL5State12_2atry_2f278(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw48_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewrite__metadataL5State12_2atry_2f278.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw48_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewrite__metadataL5State8State__1(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw48_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewrite__metadataL5State8State__1.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw48_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewrite__metadataL5State8State__2(param0, param1, param2, param3, param4) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
}
_M0DTP46f4ah6o3dsh7browser2sw48_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewrite__metadataL5State8State__2.prototype.$tag = 2;
function _M0DTP46f4ah6o3dsh7browser2sw49_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__metadataL5State8State__0(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw49_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__metadataL5State8State__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw49_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__metadataL5State8State__1(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw49_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__metadataL5State8State__1.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__active__generationL5State12_2aarm_2f284() {}
_M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__active__generationL5State12_2aarm_2f284.prototype.$tag = 0;
const _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__active__generationL5State12_2aarm_2f284__ = new _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__active__generationL5State12_2aarm_2f284();
function _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__active__generationL5State8State__1(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__active__generationL5State8State__1.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__active__generationL5State8State__2(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__active__generationL5State8State__2.prototype.$tag = 2;
function _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__client__generationL5State12_2aarm_2f289() {}
_M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__client__generationL5State12_2aarm_2f289.prototype.$tag = 0;
const _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__client__generationL5State12_2aarm_2f289__ = new _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__client__generationL5State12_2aarm_2f289();
function _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__client__generationL5State8State__1(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__client__generationL5State8State__1.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__0(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__1(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__1.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__2(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__2.prototype.$tag = 2;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__3(param0, param1, param2, param3, param4, param5) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__3.prototype.$tag = 3;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State9_2afor__4(param0, param1, param2, param3, param4, param5, param6, param7) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
  this._7 = param7;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State9_2afor__4.prototype.$tag = 4;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__5(param0, param1, param2, param3, param4, param5, param6, param7, param8) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
  this._7 = param7;
  this._8 = param8;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__5.prototype.$tag = 5;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__6(param0, param1, param2, param3, param4) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__6.prototype.$tag = 6;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__7(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__7.prototype.$tag = 7;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State12_2atry_2f305(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State12_2atry_2f305.prototype.$tag = 8;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__9(param0, param1, param2, param3, param4) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__9.prototype.$tag = 9;
function _M0TPB8MutLocalGbE(param0) {
  this.val = param0;
}
function _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2efind__legacy__generationL5State8State__0(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2efind__legacy__generationL5State8State__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewindow__client__idsL5State8State__0(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewindow__client__idsL5State8State__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__0(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__1(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__1.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__2(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__2.prototype.$tag = 2;
function _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__3(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__3.prototype.$tag = 3;
function _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__4(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__4.prototype.$tag = 4;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9_2afor__0(param0, param1, param2, param3, param4, param5) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9_2afor__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__1(param0, param1, param2, param3, param4, param5, param6) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__1.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__2(param0, param1, param2, param3, param4, param5, param6) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__2.prototype.$tag = 2;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__3(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__3.prototype.$tag = 3;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__4(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__4.prototype.$tag = 4;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9_2afor__5(param0, param1, param2, param3, param4, param5, param6, param7) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
  this._7 = param7;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9_2afor__5.prototype.$tag = 5;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__6(param0, param1, param2, param3, param4, param5, param6, param7, param8) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
  this._7 = param7;
  this._8 = param8;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__6.prototype.$tag = 6;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__7(param0, param1, param2, param3, param4, param5, param6, param7, param8) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
  this._7 = param7;
  this._8 = param8;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__7.prototype.$tag = 7;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__8(param0, param1, param2, param3, param4, param5, param6, param7, param8, param9, param10) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
  this._7 = param7;
  this._8 = param8;
  this._9 = param9;
  this._10 = param10;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__8.prototype.$tag = 8;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__9(param0, param1, param2, param3, param4, param5, param6, param7, param8, param9, param10) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
  this._7 = param7;
  this._8 = param8;
  this._9 = param9;
  this._10 = param10;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__9.prototype.$tag = 9;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__10(param0, param1, param2, param3, param4, param5, param6, param7, param8, param9, param10) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
  this._7 = param7;
  this._8 = param8;
  this._9 = param9;
  this._10 = param10;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__10.prototype.$tag = 10;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__11(param0, param1, param2, param3, param4, param5, param6, param7, param8, param9, param10) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
  this._7 = param7;
  this._8 = param8;
  this._9 = param9;
  this._10 = param10;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__11.prototype.$tag = 11;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__12(param0, param1, param2, param3, param4, param5) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__12.prototype.$tag = 12;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__13(param0, param1, param2, param3, param4, param5) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__13.prototype.$tag = 13;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__14(param0, param1, param2, param3, param4, param5, param6) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__14.prototype.$tag = 14;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__15(param0, param1, param2, param3, param4, param5) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__15.prototype.$tag = 15;
function _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__16(param0, param1, param2, param3, param4) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
}
_M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__16.prototype.$tag = 16;
function _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__0(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__1(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__1.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__2(param0, param1, param2, param3, param4) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
}
_M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__2.prototype.$tag = 2;
function _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__3(param0, param1, param2, param3, param4) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
}
_M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__3.prototype.$tag = 3;
function _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__4(param0, param1, param2, param3, param4, param5, param6) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
}
_M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__4.prototype.$tag = 4;
function _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9_2afor__5(param0, param1, param2, param3, param4, param5, param6, param7, param8) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
  this._7 = param7;
  this._8 = param8;
}
_M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9_2afor__5.prototype.$tag = 5;
function _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__6(param0, param1, param2, param3, param4, param5, param6, param7, param8, param9) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
  this._7 = param7;
  this._8 = param8;
  this._9 = param9;
}
_M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__6.prototype.$tag = 6;
function _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__7(param0, param1, param2, param3, param4, param5, param6, param7, param8, param9) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
  this._7 = param7;
  this._8 = param8;
  this._9 = param9;
}
_M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__7.prototype.$tag = 7;
function _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__8(param0, param1, param2, param3, param4, param5, param6, param7, param8, param9, param10) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
  this._6 = param6;
  this._7 = param7;
  this._8 = param8;
  this._9 = param9;
  this._10 = param10;
}
_M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__8.prototype.$tag = 8;
function _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__9(param0, param1, param2, param3, param4, param5) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
}
_M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__9.prototype.$tag = 9;
function _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__10(param0, param1, param2, param3, param4) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
}
_M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__10.prototype.$tag = 10;
function _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__11(param0, param1, param2, param3, param4) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
}
_M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__11.prototype.$tag = 11;
function _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__12(param0, param1, param2, param3, param4) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
}
_M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__12.prototype.$tag = 12;
function _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__13(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__13.prototype.$tag = 13;
function _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__0(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__1(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__1.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__2(param0) {
  this._0 = param0;
}
_M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__2.prototype.$tag = 2;
function _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__3(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__3.prototype.$tag = 3;
function _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__4(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__4.prototype.$tag = 4;
function _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__5(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__5.prototype.$tag = 5;
const _M0FP46f4ah6o3dsh7browser2sw17sw__same__promise = (left, right) => left === right;
function _M0DTP46f4ah6o3dsh7browser2sw59_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generationL5State8State__0(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw59_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generationL5State8State__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw59_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generationL5State12_2atry_2f399(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw59_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generationL5State12_2atry_2f399.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State8State__0(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State8State__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State12_2aarm_2f415(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State12_2aarm_2f415.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State8State__2(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State8State__2.prototype.$tag = 2;
function _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State8State__3(param0, param1, param2) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
}
_M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State8State__3.prototype.$tag = 3;
function _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2eserve__from__generationL5State8State__0(param0, param1, param2, param3, param4) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
}
_M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2eserve__from__generationL5State8State__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2eserve__from__generationL5State8State__1(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2eserve__from__generationL5State8State__1.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__0(param0, param1, param2, param3) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
}
_M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__0.prototype.$tag = 0;
function _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__1(param0, param1, param2, param3, param4) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
}
_M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__1.prototype.$tag = 1;
function _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__2(param0, param1, param2, param3, param4, param5) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
}
_M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__2.prototype.$tag = 2;
function _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__3(param0, param1, param2, param3, param4, param5) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
}
_M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__3.prototype.$tag = 3;
function _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__4(param0, param1, param2, param3, param4) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
}
_M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__4.prototype.$tag = 4;
function _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__5(param0, param1, param2, param3, param4, param5) {
  this._0 = param0;
  this._1 = param1;
  this._2 = param2;
  this._3 = param3;
  this._4 = param4;
  this._5 = param5;
}
_M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__5.prototype.$tag = 5;
const _M0FP092moonbitlang_2fcore_2fbuiltin_2fStringBuilder_24as_24_40moonbitlang_2fcore_2fbuiltin_2eLogger = { method_0: _M0IPB13StringBuilderPB6Logger13write__string, method_1: _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE, method_2: _M0IPB13StringBuilderPB6Logger11write__view, method_3: _M0IPB13StringBuilderPB6Logger11write__char, method_4: _M0IP016_24default__implPB6Logger28write__string__interpolationGRPB13StringBuilderE, method_5: _M0IP016_24default__implPB6Logger5writeGRPB13StringBuilderE };
const _M0FP052String_24as_24_40moonbitlang_2fcore_2fbuiltin_2eShow = { method_0: _M0IP016_24default__implPB4Show6outputGsE, method_1: _M0IPC16string6StringPB4Show10to__string };
function _M0FP15Error10to__string(_e) {
  switch (_e.$tag) {
    case 0: {
      return _M0IP016_24default__implPB4Show10to__stringGRP311moonbitlang5async9js__async7JsErrorE(_e);
    }
    case 2: {
      return "f4ah6o/dsh/browser/sw.WorkerFailure.WorkerFailure";
    }
    default: {
      return "moonbitlang/core/builtin.Cancelled.Cancelled";
    }
  }
}
const _M0MPC16string10StringView4trimN7_2abindS6831 = "\t\n\r ";
const _M0MPC16string6String4trimN7_2abindS6932 = "\t\n\r ";
const _M0MPB4Iter4nextN6constrS9909GRP411moonbitlang5async8internal9coroutine9CoroutineE = 0;
const _M0MPB4Iter4nextN6constrS9910GRP411moonbitlang5async8internal9coroutine9CoroutineE = 0;
const _M0MPB4Iter4nextN6constrS9909GcE = 0;
const _M0MPB4Iter4nextN6constrS9910GcE = 0;
const _M0MPB4Iter3newN6constrS9917GRP411moonbitlang5async8internal9coroutine9CoroutineE = 0;
const _M0MPB4Iter3newN6constrS9917GcE = 0;
const _M0FP46f4ah6o3dsh7browser2sw18generation__prefix = "dsh-shell-generation-";
const _M0FP46f4ah6o3dsh7browser2sw17meta__cache__name = "dsh-shell-meta-v1";
const _M0FP46f4ah6o3dsh7browser2sw15staging__prefix = "/__dsh_shell_staging__/";
const _M0FP46f4ah6o3dsh7browser2sw19client__pin__prefix = "/__dsh_shell_client__/";
const _M0FP46f4ah6o3dsh7browser2sw11active__key = "/__dsh_shell_active__";
const _M0FP46f4ah6o3dsh7browser2sw12pending__key = "/__dsh_shell_pending__";
const _M0FP46f4ah6o3dsh7browser2sw19text__content__type = "text/plain; charset=utf-8";
const _M0FP46f4ah6o3dsh7browser2sw20legacy__cache__names = ["dsh-shell-v1", "dsh-shell-v2"];
const _M0FP46f4ah6o3dsh7browser2sw13shell__assets = ["/", "/index.html", "/kumo-standalone.css", "/yami-kumo-components.css", "/yami-kumo-shell.css", "/manifest.webmanifest", "/icon.svg", "/moonbit/browser.js"];
const _M0FP46f4ah6o3dsh7browser2sw21shell__content__types = ["application/javascript", "application/manifest+json", "image/svg+xml", "text/css", "text/html", "text/javascript"];
const _M0FP46f4ah6o3dsh7browser2sw30has__private__cache__directiveN7_2abindS232 = ",";
const _M0FP46f4ah6o3dsh7browser2sw30has__private__cache__directiveN7_2abindS221 = "=";
const _M0FP46f4ah6o3dsh7browser2sw30is__cacheable__shell__responseN7_2abindS239 = ";";
const _M0FP46f4ah6o3dsh7browser2sw30is__cacheable__shell__responseN7_2abindS238 = "";
const _M0FPB4seed = _M0FPB12random__seed();
const _bind = [];
const _tmp = _M0MPC15deque5Deque5DequeGRP411moonbitlang5async8internal9coroutine9CoroutineE(new _M0TPB9ArrayViewGRP411moonbitlang5async8internal9coroutine9CoroutineE(_bind, 0, 0), undefined);
const _bind$2 = [];
const _M0FP411moonbitlang5async8internal9coroutine9scheduler = new _M0TP411moonbitlang5async8internal9coroutine9Scheduler(0, undefined, _tmp, _M0MPC13set3Set3SetGRP411moonbitlang5async8internal9coroutine9CoroutineE(new _M0TPB9ArrayViewGRP411moonbitlang5async8internal9coroutine9CoroutineE(_bind$2, 0, 0), undefined));
const _M0FP411moonbitlang5async8internal9coroutine22suspend__check__cancelN6constrS374 = 1;
const _M0FP46f4ah6o3dsh7browser2sw15write__metadataN6constrS1715 = false;
const _M0FP46f4ah6o3dsh7browser2sw15write__metadataN6constrS1716 = true;
const _M0FP46f4ah6o3dsh7browser2sw19refresh__in__flight = _M0MPC13ref3Ref3RefGORP311moonbitlang5async9js__async7PromiseGOsEE(_M0DTPC16option6OptionGRP311moonbitlang5async9js__async7PromiseGOsEE4None__);
const _M0MPC16string10StringView4findN6constrS9919 = 0;
const _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN6constrS1702 = false;
const _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN6constrS1703 = false;
const _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN6constrS1704 = true;
const _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN6constrS1705 = false;
const _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN6constrS1706 = false;
const _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN6constrS1707 = false;
const _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN6constrS1708 = true;
const _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN6constrS1709 = new _M0DTP46f4ah6o3dsh7browser2sw64_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__assetL5State8State__0(false);
const _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN6constrS1710 = false;
const _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN6constrS1711 = true;
const _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN6constrS1712 = false;
const _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN6constrS1713 = false;
const _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN6constrS1714 = false;
const _M0FP46f4ah6o3dsh7browser2sw19generation__counter = _M0MPC13ref3Ref3RefGiE(0);
(() => {
  _M0FP46f4ah6o3dsh7browser2sw22start__service__worker();
})();
function _M0FPB13consume4__acc(acc, input) {
  const _p = (acc >>> 0) + ((Math.imul(input, -1028477379) | 0) >>> 0) | 0;
  const _p$2 = 17;
  return Math.imul(_p << _p$2 | (_p >>> (32 - _p$2 | 0) | 0), 668265263) | 0;
}
function _M0MPB6Hasher8consume4(self, input) {
  self.acc = _M0FPB13consume4__acc(self.acc, input);
}
function _M0MPB6Hasher13combine__uint(self, value) {
  self.acc = (self.acc >>> 0) + (4 >>> 0) | 0;
  _M0MPB6Hasher8consume4(self, value);
}
function _M0MPB18UninitializedArray21clamped__view_2einnerGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, start, end) {
  const len = self.length;
  const lo = start < 0 ? 0 : start > len ? len : start;
  let hi;
  if (end === undefined) {
    hi = len;
  } else {
    const _Some = end;
    const _end = _Some;
    hi = _end < 0 ? 0 : _end > len ? len : _end;
  }
  const count = hi > lo ? hi - lo | 0 : 0;
  return new _M0TPB9ArrayViewGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, lo, lo + count | 0);
}
function _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGRP411moonbitlang5async8internal9coroutine9CoroutineEE(dst, dst_offset, src, src_offset, len) {
  if (dst === src && dst_offset < src_offset) {
    let _tmp$2 = 0;
    while (true) {
      const i = _tmp$2;
      if (i < len) {
        const _tmp$3 = dst_offset + i | 0;
        const _tmp$4 = src_offset + i | 0;
        if (_tmp$3 >>> 0 < dst.length) {
          dst[_tmp$3] = _tmp$4 >>> 0 < src.length ? src[_tmp$4] : $oob();
        } else {
          $oob();
        }
        _tmp$2 = i + 1 | 0;
        continue;
      } else {
        return;
      }
    }
  } else {
    let _tmp$2 = len - 1 | 0;
    while (true) {
      const i = _tmp$2;
      if (i >= 0) {
        const _tmp$3 = dst_offset + i | 0;
        const _tmp$4 = src_offset + i | 0;
        if (_tmp$3 >>> 0 < dst.length) {
          dst[_tmp$3] = _tmp$4 >>> 0 < src.length ? src[_tmp$4] : $oob();
        } else {
          $oob();
        }
        _tmp$2 = i - 1 | 0;
        continue;
      } else {
        return;
      }
    }
  }
}
function _M0MPB18UninitializedArray12unsafe__blitGRP411moonbitlang5async8internal9coroutine9CoroutineE(dst, dst_offset, src, src_offset, len) {
  _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGRP411moonbitlang5async8internal9coroutine9CoroutineEE(dst, dst_offset, src, src_offset, len);
}
function _M0MPB18UninitializedArray23unsafe__make__and__blitGRP411moonbitlang5async8internal9coroutine9CoroutineE(src, allocate_len, src_offset, dst_offset, blit_len) {
  const dst = new Array(allocate_len);
  _M0MPB18UninitializedArray12unsafe__blitGRP411moonbitlang5async8internal9coroutine9CoroutineE(dst, dst_offset, src, src_offset, blit_len);
  return dst;
}
function _M0MPB13StringBuilder13write__objectGiE(self, obj) {
  _M0IP016_24default__implPB4Show6outputGiE(obj, { self: self, method_table: _M0FP092moonbitlang_2fcore_2fbuiltin_2fStringBuilder_24as_24_40moonbitlang_2fcore_2fbuiltin_2eLogger });
}
function _M0MPB18UninitializedArray23make__and__blit_2einnerGRP411moonbitlang5async8internal9coroutine9CoroutineE(src, allocate_len, len, src_offset, dst_offset) {
  if (allocate_len >= 0 && (len >= 0 && (src_offset >= 0 && (dst_offset >= 0 && ((src_offset + len | 0) <= src.length && (dst_offset + len | 0) <= allocate_len))))) {
    return _M0MPB18UninitializedArray23unsafe__make__and__blitGRP411moonbitlang5async8internal9coroutine9CoroutineE(src, allocate_len, src_offset, dst_offset, len);
  } else {
    const _string_builder = _M0MPB13StringBuilder21StringBuilder_2einner(89);
    _M0IPB13StringBuilderPB6Logger13write__string(_string_builder, "bounds check failed: allocate_len = ");
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, allocate_len);
    _M0IPB13StringBuilderPB6Logger13write__string(_string_builder, ", src_offset = ");
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, src_offset);
    _M0IPB13StringBuilderPB6Logger13write__string(_string_builder, ", dst_offset = ");
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, dst_offset);
    _M0IPB13StringBuilderPB6Logger13write__string(_string_builder, ", len = ");
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, len);
    _M0IPB13StringBuilderPB6Logger13write__string(_string_builder, ", src.length = ");
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, src.length);
    return $panic();
  }
}
function _M0MPB13StringBuilder21StringBuilder_2einner(size_hint) {
  return new _M0TPB13StringBuilder("");
}
function _M0IPB13StringBuilderPB6Logger11write__char(self, ch) {
  self.val = `${self.val}${String.fromCodePoint(ch)}`;
}
function _M0IPB13StringBuilderPB6Logger13write__string(self, str) {
  self.val = `${self.val}${str}`;
}
function _M0FPB32code__point__of__surrogate__pair(leading, trailing) {
  return (((Math.imul(leading - 55296 | 0, 1024) | 0) + trailing | 0) - 56320 | 0) + 65536 | 0;
}
function _M0MPC16string6String16unsafe__char__at(self, index) {
  const c1 = self.charCodeAt(index);
  if (c1 >= 55296 && c1 <= 56319) {
    const c2 = self.charCodeAt(index + 1 | 0);
    return _M0FPB32code__point__of__surrogate__pair(c1, c2);
  } else {
    return c1;
  }
}
function _M0MPC16string10StringView12view_2einner(self, start_offset, end_offset) {
  let end_offset$2;
  if (end_offset === undefined) {
    end_offset$2 = self.end - self.start | 0;
  } else {
    const _Some = end_offset;
    end_offset$2 = _Some;
  }
  if (start_offset >= 0 && (start_offset <= end_offset$2 && end_offset$2 <= (self.end - self.start | 0))) {
    return new _M0TPC16string10StringView(self.str, self.start + start_offset | 0, self.start + end_offset$2 | 0);
  } else {
    return $panic();
  }
}
function _M0MPB6Hasher12combine__int(self, value) {
  _M0MPB6Hasher13combine__uint(self, value);
}
function _M0MPB6Hasher7combineGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, value) {
  _M0IP411moonbitlang5async8internal9coroutine9CoroutinePB4Hash13hash__combine(value, self);
}
function _M0IP016_24default__implPB2Eq10not__equalGRPC16string10StringViewE(x, y) {
  return !_M0IPC16string10StringViewPB2Eq5equal(x, y);
}
function _M0MPB6Hasher14Hasher_2einner(seed) {
  return new _M0TPB6Hasher((seed >>> 0) + (374761393 >>> 0) | 0);
}
function _M0MPB6Hasher6Hasher(seed$46$opt) {
  let seed;
  if (seed$46$opt === undefined) {
    seed = _M0FPB4seed;
  } else {
    const _Some = seed$46$opt;
    seed = _Some;
  }
  return _M0MPB6Hasher14Hasher_2einner(seed);
}
function _M0FPB14avalanche__acc(acc) {
  let acc$2 = acc;
  acc$2 = acc$2 ^ (acc$2 >>> 15 | 0);
  acc$2 = Math.imul(acc$2, -2048144777) | 0;
  acc$2 = acc$2 ^ (acc$2 >>> 13 | 0);
  acc$2 = Math.imul(acc$2, -1028477379) | 0;
  acc$2 = acc$2 ^ (acc$2 >>> 16 | 0);
  return acc$2;
}
function _M0FPB13finalize__acc(acc) {
  return _M0FPB14avalanche__acc(acc);
}
function _M0MPB6Hasher8finalize(self) {
  return _M0FPB13finalize__acc(self.acc);
}
function _M0IP016_24default__implPB4Hash4hashGRP411moonbitlang5async8internal9coroutine9CoroutineE(self) {
  const h = _M0MPB6Hasher6Hasher(undefined);
  _M0MPB6Hasher7combineGRP411moonbitlang5async8internal9coroutine9CoroutineE(h, self);
  return _M0MPB6Hasher8finalize(h);
}
function _M0IP016_24default__implPB6Logger28write__string__interpolationGRPB13StringBuilderE(self, show) {
  show.method_table.method_0(show.self, { self: self, method_table: _M0FP092moonbitlang_2fcore_2fbuiltin_2fStringBuilder_24as_24_40moonbitlang_2fcore_2fbuiltin_2eLogger });
}
function _M0IP016_24default__implPB6Logger5writeGRPB13StringBuilderE(self, show) {
  show.method_table.method_0(show.self, { self: self, method_table: _M0FP092moonbitlang_2fcore_2fbuiltin_2fStringBuilder_24as_24_40moonbitlang_2fcore_2fbuiltin_2eLogger });
}
function _M0MPC16string6String21clamped__view_2einner(self, start, end) {
  const len = self.length;
  let lo = start < 0 ? 0 : start > len ? len : start;
  let hi;
  if (end === undefined) {
    hi = len;
  } else {
    const _Some = end;
    const _e = _Some;
    hi = _e < 0 ? 0 : _e > len ? len : _e;
  }
  let _tmp$2;
  if (lo > 0) {
    let _tmp$3;
    if (lo < len) {
      let _tmp$4;
      const _p = self.charCodeAt(lo);
      if (_p >= 56320 && _p <= 57343) {
        const _p$2 = self.charCodeAt(lo - 1 | 0);
        _tmp$4 = _p$2 >= 55296 && _p$2 <= 56319;
      } else {
        _tmp$4 = false;
      }
      _tmp$3 = _tmp$4;
    } else {
      _tmp$3 = false;
    }
    _tmp$2 = _tmp$3;
  } else {
    _tmp$2 = false;
  }
  if (_tmp$2) {
    lo = lo + 1 | 0;
  }
  let _tmp$3;
  if (hi > 0) {
    let _tmp$4;
    if (hi < len) {
      let _tmp$5;
      const _p = self.charCodeAt(hi);
      if (_p >= 56320 && _p <= 57343) {
        const _p$2 = self.charCodeAt(hi - 1 | 0);
        _tmp$5 = _p$2 >= 55296 && _p$2 <= 56319;
      } else {
        _tmp$5 = false;
      }
      _tmp$4 = _tmp$5;
    } else {
      _tmp$4 = false;
    }
    _tmp$3 = _tmp$4;
  } else {
    _tmp$3 = false;
  }
  if (_tmp$3) {
    hi = hi - 1 | 0;
  }
  return lo >= hi ? new _M0TPC16string10StringView(self, lo, lo) : new _M0TPC16string10StringView(self, lo, hi);
}
function _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE(self, value, start, len) {
  _M0IPB13StringBuilderPB6Logger11write__view(self, _M0MPC16string6String21clamped__view_2einner(value, start, start + len | 0));
}
function _M0IP016_24default__implPB4Show6outputGiE(self, logger) {
  logger.method_table.method_0(logger.self, _M0IPC13int3IntPB4Show10to__string(self));
}
function _M0IP016_24default__implPB4Show6outputGsE(self, logger) {
  logger.method_table.method_0(logger.self, self);
}
function _M0IP016_24default__implPB4Show10to__stringGRP311moonbitlang5async9js__async7JsErrorE(self) {
  const logger = _M0MPB13StringBuilder21StringBuilder_2einner(0);
  _M0IP311moonbitlang5async9js__async7JsErrorPB4Show6output(self, { self: logger, method_table: _M0FP092moonbitlang_2fcore_2fbuiltin_2fStringBuilder_24as_24_40moonbitlang_2fcore_2fbuiltin_2eLogger });
  return logger.val;
}
function _M0MPB4Iter4nextGRP411moonbitlang5async8internal9coroutine9CoroutineE(self) {
  const _func = self.f;
  const result = _func();
  const _bind$3 = self.size_hint;
  if (result === undefined) {
    self.size_hint = _M0MPB4Iter4nextN6constrS9910GRP411moonbitlang5async8internal9coroutine9CoroutineE;
  } else {
    if (_bind$3 === undefined) {
    } else {
      const _Some = _bind$3;
      const _n = _Some;
      self.size_hint = _n > 0 ? _n - 1 | 0 : _M0MPB4Iter4nextN6constrS9909GRP411moonbitlang5async8internal9coroutine9CoroutineE;
    }
  }
  return result;
}
function _M0MPB4Iter4nextGcE(self) {
  const _func = self.f;
  const result = _func();
  const _bind$3 = self.size_hint;
  if (result === -1) {
    self.size_hint = _M0MPB4Iter4nextN6constrS9910GcE;
  } else {
    if (_bind$3 === undefined) {
    } else {
      const _Some = _bind$3;
      const _n = _Some;
      self.size_hint = _n > 0 ? _n - 1 | 0 : _M0MPB4Iter4nextN6constrS9909GcE;
    }
  }
  return result;
}
function _M0MPC13int3Int18to__string_2einner(self, radix) {
  return _M0FPB19int__to__string__js(self, radix);
}
function _M0MPB4Iter3newGRP411moonbitlang5async8internal9coroutine9CoroutineE(f, size_hint) {
  let size_hint$2;
  if (size_hint === undefined) {
    size_hint$2 = undefined;
  } else {
    const _Some = size_hint;
    const _n = _Some;
    size_hint$2 = _n > 0 ? _n : _M0MPB4Iter3newN6constrS9917GRP411moonbitlang5async8internal9coroutine9CoroutineE;
  }
  return new _M0TPB4IterGRP411moonbitlang5async8internal9coroutine9CoroutineE(f, size_hint$2);
}
function _M0MPB4Iter3newGcE(f, size_hint) {
  let size_hint$2;
  if (size_hint === undefined) {
    size_hint$2 = undefined;
  } else {
    const _Some = size_hint;
    const _n = _Some;
    size_hint$2 = _n > 0 ? _n : _M0MPB4Iter3newN6constrS9917GcE;
  }
  return new _M0TPB4IterGcE(f, size_hint$2);
}
function _M0MPC16string10StringView9to__owned(self) {
  return self.str.substring(self.start, self.end);
}
function _M0MPC16string10StringView4iter(self) {
  const start = self.start;
  const end = self.end;
  const index = new _M0TPB8MutLocalGiE(start);
  return _M0MPB4Iter3newGcE(() => {
    if (index.val < end) {
      const c1 = self.str.charCodeAt(index.val);
      if (c1 >= 55296 && c1 <= 56319 && (index.val + 1 | 0) < self.end) {
        const c2 = self.str.charCodeAt(index.val + 1 | 0);
        if (c2 >= 56320 && c2 <= 57343) {
          index.val = index.val + 2 | 0;
          return _M0FPB32code__point__of__surrogate__pair(c1, c2);
        }
      }
      index.val = index.val + 1 | 0;
      return c1;
    } else {
      return -1;
    }
  }, undefined);
}
function _M0MPC16string6String20unsafe__range__equal(self, self_off, other, other_off, len) {
  let _tmp$2 = 0;
  while (true) {
    const i = _tmp$2;
    if (i < len) {
      const _p = self.charCodeAt(self_off + i | 0);
      const _p$2 = other.charCodeAt(other_off + i | 0);
      if (_p === _p$2) {
      } else {
        return false;
      }
      _tmp$2 = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return true;
}
function _M0IPC16string10StringViewPB2Eq5equal(self, other) {
  const len = self.end - self.start | 0;
  if (len === (other.end - other.start | 0)) {
    if (self.str === other.str && self.start === other.start) {
      return true;
    }
    return _M0MPC16string6String20unsafe__range__equal(self.str, self.start, other.str, other.start, len);
  } else {
    return false;
  }
}
function _M0MPC16string6String31offset__of__nth__char__backward(self, n, start_offset, end_offset) {
  let _tmp$2 = end_offset;
  let _tmp$3 = 0;
  while (true) {
    const utf16_offset = _tmp$2;
    const char_count = _tmp$3;
    if ((utf16_offset - 1 | 0) >= start_offset && char_count < n) {
      const c = self.charCodeAt(utf16_offset - 1 | 0);
      if (c >= 56320 && c <= 57343) {
        _tmp$2 = utf16_offset - 2 | 0;
        _tmp$3 = char_count + 1 | 0;
        continue;
      } else {
        _tmp$2 = utf16_offset - 1 | 0;
        _tmp$3 = char_count + 1 | 0;
        continue;
      }
    } else {
      return char_count < n || utf16_offset < start_offset ? undefined : utf16_offset;
    }
  }
}
function _M0MPC16string6String30offset__of__nth__char__forward(self, n, start_offset, end_offset) {
  if (start_offset >= 0 && start_offset <= end_offset) {
    let _tmp$2 = start_offset;
    let _tmp$3 = 0;
    while (true) {
      const utf16_offset = _tmp$2;
      const char_count = _tmp$3;
      if (utf16_offset < end_offset && char_count < n) {
        const c = self.charCodeAt(utf16_offset);
        if (c >= 55296 && c <= 56319) {
          _tmp$2 = utf16_offset + 2 | 0;
          _tmp$3 = char_count + 1 | 0;
          continue;
        } else {
          _tmp$2 = utf16_offset + 1 | 0;
          _tmp$3 = char_count + 1 | 0;
          continue;
        }
      } else {
        return char_count < n || utf16_offset >= end_offset ? undefined : utf16_offset;
      }
    }
  } else {
    return $panic();
  }
}
function _M0MPC16string6String29offset__of__nth__char_2einner(self, i, start_offset, end_offset) {
  let end_offset$2;
  if (end_offset === undefined) {
    end_offset$2 = self.length;
  } else {
    const _Some = end_offset;
    end_offset$2 = _Some;
  }
  return i >= 0 ? _M0MPC16string6String30offset__of__nth__char__forward(self, i, start_offset, end_offset$2) : _M0MPC16string6String31offset__of__nth__char__backward(self, -i | 0, start_offset, end_offset$2);
}
function _M0MPC16string6String12view_2einner(self, start_offset, end_offset) {
  let end_offset$2;
  if (end_offset === undefined) {
    end_offset$2 = self.length;
  } else {
    const _Some = end_offset;
    end_offset$2 = _Some;
  }
  if (start_offset >= 0 && (start_offset <= end_offset$2 && end_offset$2 <= self.length)) {
    return new _M0TPC16string10StringView(self, start_offset, end_offset$2);
  } else {
    return $panic();
  }
}
function _M0IPB13StringBuilderPB6Logger11write__view(self, str) {
  self.val = `${self.val}${_M0MPC16string10StringView9to__owned(str)}`;
}
function _M0FPB19kmp__failure__table(pattern) {
  const m = pattern.end - pattern.start | 0;
  const table = $make_array_len_and_init(m, 0);
  let k = 0;
  let _tmp$2 = 1;
  while (true) {
    const i = _tmp$2;
    if (i < m) {
      const c = pattern.str.charCodeAt(pattern.start + i | 0);
      while (true) {
        let _tmp$3;
        if (k > 0) {
          const _p = pattern.str.charCodeAt(pattern.start + k | 0);
          _tmp$3 = c !== _p;
        } else {
          _tmp$3 = false;
        }
        if (_tmp$3) {
          const _tmp$4 = k - 1 | 0;
          k = _tmp$4 >>> 0 < table.length ? table[_tmp$4] : $oob();
          continue;
        } else {
          break;
        }
      }
      const _p = pattern.str.charCodeAt(pattern.start + k | 0);
      if (c === _p) {
        k = k + 1 | 0;
      }
      if (i >>> 0 < table.length) {
        table[i] = k;
      } else {
        $oob();
      }
      _tmp$2 = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return table;
}
function _M0FPB24find__pattern__kmp__from(target, pattern, start) {
  const n = target.end - target.start | 0;
  const m = pattern.end - pattern.start | 0;
  const table = _M0FPB19kmp__failure__table(pattern);
  let k = 0;
  let _tmp$2 = start;
  while (true) {
    const i = _tmp$2;
    if (i < n) {
      const c = target.str.charCodeAt(target.start + i | 0);
      while (true) {
        let _tmp$3;
        if (k > 0) {
          const _p = pattern.str.charCodeAt(pattern.start + k | 0);
          _tmp$3 = c !== _p;
        } else {
          _tmp$3 = false;
        }
        if (_tmp$3) {
          const _tmp$4 = k - 1 | 0;
          k = _tmp$4 >>> 0 < table.length ? table[_tmp$4] : $oob();
          continue;
        } else {
          break;
        }
      }
      const _p = pattern.str.charCodeAt(pattern.start + k | 0);
      if (c === _p) {
        k = k + 1 | 0;
      }
      if (k === m) {
        return (i - m | 0) + 1 | 0;
      }
      _tmp$2 = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return undefined;
}
function _M0FPB36find__two__anchor__candidate__scalar(data, start, candidate_end, first, last_offset, last) {
  let _tmp$2 = start;
  while (true) {
    const pos = _tmp$2;
    if (pos < candidate_end) {
      let _tmp$3;
      const _p = data.charCodeAt(pos);
      if (_p === first) {
        const _p$2 = data.charCodeAt(pos + last_offset | 0);
        _tmp$3 = _p$2 === last;
      } else {
        _tmp$3 = false;
      }
      if (_tmp$3) {
        return pos;
      }
      _tmp$2 = pos + 1 | 0;
      continue;
    } else {
      return -1;
    }
  }
}
function _M0FPB42find__two__anchor__candidate__from__string(data, start, candidate_end, first, last_offset, last) {
  return _M0FPB36find__two__anchor__candidate__scalar(data, start, candidate_end, first, last_offset, last);
}
function _M0FPB21string__ranges__equal(left, left_start, right, right_start, length) {
  let _tmp$2 = 0;
  while (true) {
    const i = _tmp$2;
    if (i < length) {
      const _p = left.charCodeAt(left_start + i | 0);
      const _p$2 = right.charCodeAt(right_start + i | 0);
      if (_p !== _p$2) {
        return false;
      }
      _tmp$2 = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return true;
}
function _M0FPB22find__by__two__anchors(target, pattern) {
  const target_len = target.end - target.start | 0;
  const pattern_len = pattern.end - pattern.start | 0;
  const target_start = target.start;
  const pattern_start = pattern.start;
  const last_offset = pattern_len - 1 | 0;
  const candidate_end = ((target_start + target_len | 0) - pattern_len | 0) + 1 | 0;
  const first = pattern.str.charCodeAt(pattern.start);
  const last = pattern.str.charCodeAt(pattern.start + last_offset | 0);
  const middle_len = last_offset - 1 | 0;
  let _tmp$2 = target_start;
  let _tmp$3 = 0;
  while (true) {
    const pos = _tmp$2;
    const failures = _tmp$3;
    if (pos < candidate_end) {
      const found = _M0FPB42find__two__anchor__candidate__from__string(target.str, pos, candidate_end, first, last_offset, last);
      if (found < 0) {
        return undefined;
      }
      if (_M0FPB21string__ranges__equal(target.str, found + 1 | 0, pattern.str, pattern_start + 1 | 0, middle_len)) {
        return found - target_start | 0;
      }
      const failures$2 = failures + 1 | 0;
      const scanned = found - target_start | 0;
      if (failures$2 > 64 || failures$2 > (4 + (scanned / 8 | 0) | 0)) {
        return _M0FPB24find__pattern__kmp__from(target, pattern, scanned + 1 | 0);
      }
      _tmp$2 = found + 1 | 0;
      _tmp$3 = failures$2;
      continue;
    } else {
      return undefined;
    }
  }
}
function _M0FPB24find__code__unit__scalar(data, start, end, code) {
  let _tmp$2 = start;
  while (true) {
    const pos = _tmp$2;
    if (pos < end) {
      const _p = data.charCodeAt(pos);
      if (_p === code) {
        return pos;
      }
      _tmp$2 = pos + 1 | 0;
      continue;
    } else {
      return -1;
    }
  }
}
function _M0FPB30find__code__unit__from__string(data, start, end, code) {
  return _M0FPB24find__code__unit__scalar(data, start, end, code);
}
function _M0FPB28find__code__unit__from__view(target, start, end, code) {
  const target_start = target.start;
  const found = _M0FPB30find__code__unit__from__string(target.str, target_start + start | 0, target_start + end | 0, code);
  return found < 0 ? -1 : found - target_start | 0;
}
function _M0MPC16string10StringView4find(self, str) {
  const pattern_len = str.end - str.start | 0;
  switch (pattern_len) {
    case 0: {
      return _M0MPC16string10StringView4findN6constrS9919;
    }
    case 1: {
      const found = _M0FPB28find__code__unit__from__view(self, 0, self.end - self.start | 0, str.str.charCodeAt(str.start));
      return found < 0 ? undefined : found;
    }
    default: {
      return pattern_len > (self.end - self.start | 0) ? undefined : _M0FPB22find__by__two__anchors(self, str);
    }
  }
}
function _M0IPC16string6StringPB4Show10to__string(self) {
  return self;
}
function _M0MPC16string6String8find__by(self, pred) {
  const _p = new _M0TPC16string10StringView(self, 0, self.length);
  const _p$2 = _p.str;
  const _p$3 = _p.start;
  const _p$4 = _p.end;
  let _tmp$2 = _p$3;
  let _tmp$3 = 0;
  while (true) {
    const _p$5 = _tmp$2;
    const _p$6 = _tmp$3;
    if (_p$5 < _p$4) {
      let _p$7;
      let _p$8;
      _L: {
        const _p$9 = _p$2.charCodeAt(_p$5);
        if (_p$9 >= 55296 && _p$9 <= 56319 && (_p$5 + 1 | 0) < _p$4) {
          const _p$10 = _p$2.charCodeAt(_p$5 + 1 | 0);
          if (_p$10 >= 56320 && _p$10 <= 57343) {
            const _tmp$4 = _p$5 + 2 | 0;
            const _p$11 = (((Math.imul(_p$9 - 55296 | 0, 1024) | 0) + _p$10 | 0) - 56320 | 0) + 65536 | 0;
            _p$7 = _tmp$4;
            _p$8 = _p$11;
            break _L;
          } else {
            const _tmp$4 = _p$5 + 1 | 0;
            const _p$11 = _p$9;
            _p$7 = _tmp$4;
            _p$8 = _p$11;
            break _L;
          }
        } else {
          const _tmp$4 = _p$5 + 1 | 0;
          const _p$10 = _p$9;
          _p$7 = _tmp$4;
          _p$8 = _p$10;
          break _L;
        }
      }
      if (pred(_p$8)) {
        return _p$6;
      }
      _tmp$2 = _p$7;
      const _p$9 = _p$8;
      _tmp$3 = _p$6 + (_p$9 <= 65535 ? 1 : 2) | 0;
      continue;
    } else {
      return undefined;
    }
  }
}
function _M0MPC16string10StringView11has__prefix(self, str) {
  const str_len = str.end - str.start | 0;
  if (str_len <= (self.end - self.start | 0)) {
    let _tmp$2;
    if (str_len === 0) {
      _tmp$2 = true;
    } else {
      const _p = self.str.charCodeAt(self.start);
      const _p$2 = str.str.charCodeAt(str.start);
      _tmp$2 = _p === _p$2;
    }
    if (_tmp$2) {
      return _M0MPC16string6String20unsafe__range__equal(self.str, self.start, str.str, str.start, str_len);
    } else {
      return false;
    }
  } else {
    return false;
  }
}
function _M0MPC16string6String11has__prefix(self, str) {
  return _M0MPC16string10StringView11has__prefix(new _M0TPC16string10StringView(self, 0, self.length), str);
}
function _M0MPC15array5Array4pushGsE(self, value) {
  _M0MPB7JSArray4push(self, value);
}
function _M0FPB36string__contains__code__unit__scalar(str, start, end, code) {
  let _tmp$2 = start;
  while (true) {
    const i = _tmp$2;
    if (i < end) {
      const _p = str.charCodeAt(i);
      if (_p === code) {
        return true;
      }
      _tmp$2 = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return false;
}
function _M0FPB28string__contains__code__unit(str, start, end, code) {
  return _M0FPB36string__contains__code__unit__scalar(str, start, end, code);
}
function _M0MPC16string10StringView20contains__code__unit(self, code) {
  return _M0FPB28string__contains__code__unit(self.str, self.start, self.end, code);
}
function _M0FPB23build__ascii__char__set(chars) {
  let bits0 = 0;
  let bits1 = 0;
  let bits2 = 0;
  let bits3 = 0;
  const _bind$3 = chars.str;
  const _bind$4 = chars.start;
  const _bind$5 = chars.end;
  let _tmp$2 = _bind$4;
  while (true) {
    const _string_index = _tmp$2;
    if (_string_index < _bind$5) {
      let _decoded_next_string_index;
      let _decoded_char;
      _L: {
        const _bind$6 = _bind$3.charCodeAt(_string_index);
        if (_bind$6 >= 55296 && _bind$6 <= 56319 && (_string_index + 1 | 0) < _bind$5) {
          const _bind$7 = _bind$3.charCodeAt(_string_index + 1 | 0);
          if (_bind$7 >= 56320 && _bind$7 <= 57343) {
            const _tmp$3 = _string_index + 2 | 0;
            const _p = (((Math.imul(_bind$6 - 55296 | 0, 1024) | 0) + _bind$7 | 0) - 56320 | 0) + 65536 | 0;
            _decoded_next_string_index = _tmp$3;
            _decoded_char = _p;
            break _L;
          } else {
            const _tmp$3 = _string_index + 1 | 0;
            const _p = _bind$6;
            _decoded_next_string_index = _tmp$3;
            _decoded_char = _p;
            break _L;
          }
        } else {
          const _tmp$3 = _string_index + 1 | 0;
          const _p = _bind$6;
          _decoded_next_string_index = _tmp$3;
          _decoded_char = _p;
          break _L;
        }
      }
      const code = _decoded_char;
      if (code >>> 0 < 128 >>> 0) {
        const bit = 1 << (code & 31);
        const _bind$6 = code >>> 5 | 0;
        switch (_bind$6) {
          case 0: {
            bits0 = bits0 | bit;
            break;
          }
          case 1: {
            bits1 = bits1 | bit;
            break;
          }
          case 2: {
            bits2 = bits2 | bit;
            break;
          }
          default: {
            bits3 = bits3 | bit;
          }
        }
      } else {
        return undefined;
      }
      _tmp$2 = _decoded_next_string_index;
      continue;
    } else {
      break;
    }
  }
  return { _0: bits0, _1: bits1, _2: bits2, _3: bits3 };
}
function _M0FPB26ascii__char__set__contains(bits0, bits1, bits2, bits3, code) {
  if (code >>> 0 < 128 >>> 0) {
    const bit = 1 << (code & 31);
    const _bind$3 = code >>> 5 | 0;
    switch (_bind$3) {
      case 0: {
        return (bits0 & bit) !== 0;
      }
      case 1: {
        return (bits1 & bit) !== 0;
      }
      case 2: {
        return (bits2 & bit) !== 0;
      }
      default: {
        return (bits3 & bit) !== 0;
      }
    }
  } else {
    return false;
  }
}
function _M0FPB34string__trim__start__ascii__scalar(str, start, end, bits0, bits1, bits2, bits3) {
  let _tmp$2 = start;
  while (true) {
    const pos = _tmp$2;
    let _tmp$3;
    if (pos < end) {
      const _p = str.charCodeAt(pos);
      _tmp$3 = _M0FPB26ascii__char__set__contains(bits0, bits1, bits2, bits3, _p);
    } else {
      _tmp$3 = false;
    }
    if (_tmp$3) {
      _tmp$2 = pos + 1 | 0;
      continue;
    } else {
      return pos;
    }
  }
}
function _M0FPB32string__trim__end__ascii__scalar(str, start, end, bits0, bits1, bits2, bits3) {
  let _tmp$2 = end;
  while (true) {
    const pos = _tmp$2;
    let _tmp$3;
    if (pos > start) {
      const _p = str.charCodeAt(pos - 1 | 0);
      _tmp$3 = _M0FPB26ascii__char__set__contains(bits0, bits1, bits2, bits3, _p);
    } else {
      _tmp$3 = false;
    }
    if (_tmp$3) {
      _tmp$2 = pos - 1 | 0;
      continue;
    } else {
      return pos;
    }
  }
}
function _M0FPB26string__trim__start__ascii(str, start, end, _chars, bits0, bits1, bits2, bits3) {
  return _M0FPB34string__trim__start__ascii__scalar(str, start, end, bits0, bits1, bits2, bits3);
}
function _M0FPB24string__trim__end__ascii(str, start, end, _chars, bits0, bits1, bits2, bits3) {
  return _M0FPB32string__trim__end__ascii__scalar(str, start, end, bits0, bits1, bits2, bits3);
}
function _M0MPC16string10StringView14contains__char(self, c) {
  const len = self.end - self.start | 0;
  if (len > 0) {
    const c$2 = c;
    if (c$2 >= 0 && c$2 <= 65535) {
      return _M0MPC16string10StringView20contains__code__unit(self, c$2 & 65535);
    } else {
      if (c$2 < 0) {
        return false;
      } else {
        if (len >= 2) {
          const adj = c$2 - 65536 | 0;
          const high = 55296 + (adj >> 10) | 0;
          if (high <= 65535) {
            const high$2 = high & 65535;
            const low = (56320 + (adj & 1023) | 0) & 65535;
            let _tmp$2 = 0;
            while (true) {
              const i = _tmp$2;
              if (i < (len - 1 | 0)) {
                const _p = self.str.charCodeAt(self.start + i | 0);
                if (_p === high$2) {
                  const _p$2 = self.str.charCodeAt(self.start + (i + 1 | 0) | 0);
                  if (_p$2 === low) {
                    return true;
                  }
                  _tmp$2 = i + 2 | 0;
                  continue;
                }
                _tmp$2 = i + 1 | 0;
                continue;
              } else {
                break;
              }
            }
          } else {
            return false;
          }
        } else {
          return false;
        }
      }
    }
    return false;
  } else {
    return false;
  }
}
function _M0MPC16string10StringView24trim__start__with__chars(self, chars) {
  let _tmp$2 = self;
  while (true) {
    const x = _tmp$2;
    if ((x.end - x.start | 0) === 0) {
      return x;
    } else {
      const _c = _M0MPC16string6String16unsafe__char__at(x.str, _M0MPC16string6String29offset__of__nth__char_2einner(x.str, 0, x.start, x.end));
      const _tmp$3 = x.str;
      const _bind$3 = _M0MPC16string6String29offset__of__nth__char_2einner(x.str, 1, x.start, x.end);
      let _tmp$4;
      if (_bind$3 === undefined) {
        _tmp$4 = x.end;
      } else {
        const _Some = _bind$3;
        _tmp$4 = _Some;
      }
      const _x = new _M0TPC16string10StringView(_tmp$3, _tmp$4, x.end);
      if (_M0MPC16string10StringView14contains__char(chars, _c)) {
        _tmp$2 = _x;
        continue;
      } else {
        return x;
      }
    }
  }
}
function _M0MPC16string10StringView22trim__end__with__chars(self, chars) {
  let _tmp$2 = self;
  while (true) {
    const x = _tmp$2;
    if ((x.end - x.start | 0) === 0) {
      return x;
    } else {
      const _c = _M0MPC16string6String16unsafe__char__at(x.str, _M0MPC16string6String29offset__of__nth__char_2einner(x.str, -1, x.start, x.end));
      const _x = new _M0TPC16string10StringView(x.str, x.start, _M0MPC16string6String29offset__of__nth__char_2einner(x.str, -1, x.start, x.end));
      if (_M0MPC16string10StringView14contains__char(chars, _c)) {
        _tmp$2 = _x;
        continue;
      } else {
        return x;
      }
    }
  }
}
function _M0MPC16string10StringView12trim_2einner(self, chars) {
  const _bind$3 = _M0FPB23build__ascii__char__set(chars);
  if (_bind$3 === undefined) {
    return _M0MPC16string10StringView22trim__end__with__chars(_M0MPC16string10StringView24trim__start__with__chars(self, chars), chars);
  } else {
    const _Some = _bind$3;
    const _x = _Some;
    const _bits0 = _x._0;
    const _bits1 = _x._1;
    const _bits2 = _x._2;
    const _bits3 = _x._3;
    const start = _M0FPB26string__trim__start__ascii(self.str, self.start, self.end, chars, _bits0, _bits1, _bits2, _bits3);
    const end = _M0FPB24string__trim__end__ascii(self.str, start, self.end, chars, _bits0, _bits1, _bits2, _bits3);
    return new _M0TPC16string10StringView(self.str, start, end);
  }
}
function _M0MPC16string10StringView4trim(self, chars$46$opt) {
  let chars;
  if (chars$46$opt === undefined) {
    chars = new _M0TPC16string10StringView(_M0MPC16string10StringView4trimN7_2abindS6831, 0, _M0MPC16string10StringView4trimN7_2abindS6831.length);
  } else {
    const _Some = chars$46$opt;
    chars = _Some;
  }
  return _M0MPC16string10StringView12trim_2einner(self, chars);
}
function _M0MPC16string6String12trim_2einner(self, chars) {
  return _M0MPC16string10StringView12trim_2einner(new _M0TPC16string10StringView(self, 0, self.length), chars);
}
function _M0MPC16string6String4trim(self, chars$46$opt) {
  let chars;
  if (chars$46$opt === undefined) {
    chars = new _M0TPC16string10StringView(_M0MPC16string6String4trimN7_2abindS6932, 0, _M0MPC16string6String4trimN7_2abindS6932.length);
  } else {
    const _Some = chars$46$opt;
    chars = _Some;
  }
  return _M0MPC16string6String12trim_2einner(self, chars);
}
function _M0MPB4Iter3mapGcRPC16string10StringViewE(self, f) {
  return new _M0TPB4IterGRPC16string10StringViewE(() => {
    const _bind$3 = _M0MPB4Iter4nextGcE(self);
    if (_bind$3 === -1) {
      return undefined;
    } else {
      const _Some = _bind$3;
      const _x = _Some;
      return f(_x);
    }
  }, self.size_hint);
}
function _M0IPC14char4CharPB4Show10to__string(self) {
  return String.fromCodePoint(self);
}
function _M0MPC16string10StringView5split(self, sep) {
  const sep_len = sep.end - sep.start | 0;
  if (sep_len === 0) {
    return _M0MPB4Iter3mapGcRPC16string10StringViewE(_M0MPC16string10StringView4iter(self), (c) => _M0MPC16string6String12view_2einner(_M0IPC14char4CharPB4Show10to__string(c), 0, undefined));
  }
  const remaining = new _M0TPB8MutLocalGORPC16string10StringViewE(self);
  return _M0MPB4Iter3newGRP411moonbitlang5async8internal9coroutine9CoroutineE(() => {
    const _bind$3 = remaining.val;
    if (_bind$3 === undefined) {
      return undefined;
    } else {
      const _Some = _bind$3;
      const _view = _Some;
      const _bind$4 = _M0MPC16string10StringView4find(_view, sep);
      if (_bind$4 === undefined) {
        remaining.val = undefined;
        return _view;
      } else {
        const _Some$2 = _bind$4;
        const _end = _Some$2;
        remaining.val = _M0MPC16string10StringView12view_2einner(_view, _end + sep_len | 0, undefined);
        return _M0MPC16string10StringView12view_2einner(_view, 0, _end);
      }
    }
  }, undefined);
}
function _M0MPC16string6String5split(self, sep) {
  return _M0MPC16string10StringView5split(new _M0TPC16string10StringView(self, 0, self.length), sep);
}
function _M0MPB4Iter9to__arrayGRPC16string10StringViewE(self) {
  const _bind$3 = self.size_hint;
  let result;
  if (_bind$3 === undefined) {
    result = [];
  } else {
    result = [];
  }
  while (true) {
    const _bind$4 = _M0MPB4Iter4nextGRP411moonbitlang5async8internal9coroutine9CoroutineE(self);
    if (_bind$4 === undefined) {
      break;
    } else {
      const _Some = _bind$4;
      const _x = _Some;
      _M0MPC15array5Array4pushGsE(result, _x);
      continue;
    }
  }
  return result;
}
function _M0MPC14char4Char20is__ascii__uppercase(self) {
  return self >= 65 && self <= 90;
}
function _M0MPC16string6String9to__lower(self) {
  const _bind$3 = _M0MPC16string6String8find__by(self, (c) => _M0MPC14char4Char20is__ascii__uppercase(c));
  if (_bind$3 === undefined) {
    return self;
  } else {
    const _Some = _bind$3;
    const _idx = _Some;
    const buf = _M0MPB13StringBuilder21StringBuilder_2einner(self.length);
    const head = _M0MPC16string6String12view_2einner(self, 0, _idx);
    _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE(buf, head.str, head.start, head.end - head.start | 0);
    const _bind$4 = _M0MPC16string6String12view_2einner(self, _idx, undefined);
    const _bind$5 = _bind$4.str;
    const _bind$6 = _bind$4.start;
    const _bind$7 = _bind$4.end;
    let _tmp$2 = _bind$6;
    while (true) {
      const _string_index = _tmp$2;
      if (_string_index < _bind$7) {
        let _decoded_next_string_index;
        let _decoded_char;
        _L: {
          const _bind$8 = _bind$5.charCodeAt(_string_index);
          if (_bind$8 >= 55296 && _bind$8 <= 56319 && (_string_index + 1 | 0) < _bind$7) {
            const _bind$9 = _bind$5.charCodeAt(_string_index + 1 | 0);
            if (_bind$9 >= 56320 && _bind$9 <= 57343) {
              const _tmp$3 = _string_index + 2 | 0;
              const _p = (((Math.imul(_bind$8 - 55296 | 0, 1024) | 0) + _bind$9 | 0) - 56320 | 0) + 65536 | 0;
              _decoded_next_string_index = _tmp$3;
              _decoded_char = _p;
              break _L;
            } else {
              const _tmp$3 = _string_index + 1 | 0;
              const _p = _bind$8;
              _decoded_next_string_index = _tmp$3;
              _decoded_char = _p;
              break _L;
            }
          } else {
            const _tmp$3 = _string_index + 1 | 0;
            const _p = _bind$8;
            _decoded_next_string_index = _tmp$3;
            _decoded_char = _p;
            break _L;
          }
        }
        if (_M0MPC14char4Char20is__ascii__uppercase(_decoded_char)) {
          _M0IPB13StringBuilderPB6Logger11write__char(buf, _decoded_char + 32 | 0);
        } else {
          _M0IPB13StringBuilderPB6Logger11write__char(buf, _decoded_char);
        }
        _tmp$2 = _decoded_next_string_index;
        continue;
      } else {
        break;
      }
    }
    return buf.val;
  }
}
function _M0IPC13int3IntPB4Show10to__string(self) {
  return _M0MPC13int3Int18to__string_2einner(self, 10);
}
function _M0MPC15array9ArrayView4iterGsE(self) {
  const i = new _M0TPB8MutLocalGiE(0);
  const len = self.end - self.start | 0;
  return _M0MPB4Iter3newGRP411moonbitlang5async8internal9coroutine9CoroutineE(() => {
    if (i.val < len) {
      const elem = self.buf[self.start + i.val | 0];
      i.val = i.val + 1 | 0;
      return elem;
    } else {
      return undefined;
    }
  }, len);
}
function _M0MPC15array10FixedArray4iterGsE(self) {
  return _M0MPC15array9ArrayView4iterGsE(new _M0TPB9ArrayViewGsE(self, 0, self.length));
}
function _M0MPC15array13ReadOnlyArray4iterGsE(self) {
  return _M0MPC15array10FixedArray4iterGsE(self);
}
function _M0MPC15array10FixedArray8containsGsE(self, value) {
  const _bind$3 = self.length;
  let _tmp$2 = 0;
  while (true) {
    const _ = _tmp$2;
    if (_ < _bind$3) {
      const x = self[_];
      if (x === value) {
        return true;
      }
      _tmp$2 = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return false;
}
function _M0MPC15array13ReadOnlyArray8containsGsE(self, value) {
  return _M0MPC15array10FixedArray8containsGsE(self, value);
}
function _M0MPC16option6Option6unwrapGRPB5ArrayGsEE(self) {
  if (self.$tag === 0) {
    return $panic();
  } else {
    const _Some = self;
    return _Some._0;
  }
}
function _M0MPC13int3Int20next__power__of__two(self) {
  if (self >= 0) {
    if (self <= 1) {
      return 1;
    }
    if (self > 1073741824) {
      return 1073741824;
    }
    return (2147483647 >> (Math.clz32(self - 1 | 0) - 1 | 0)) + 1 | 0;
  } else {
    return $panic();
  }
}
function _M0IPC13int3IntPB4Hash13hash__combine(self, hasher) {
  _M0MPB6Hasher12combine__int(hasher, self);
}
function _M0MPC15array5Array2atGRPC16string10StringViewE(self, index) {
  const len = self.length;
  return index >= 0 && index < len ? self[index] : $panic();
}
function _M0MPC15array5Array8containsGsE(self, value) {
  const _bind$3 = self.length;
  let _tmp$2 = 0;
  while (true) {
    const _ = _tmp$2;
    if (_ < _bind$3) {
      const v = self[_];
      if (v === value) {
        return true;
      }
      _tmp$2 = _ + 1 | 0;
      continue;
    } else {
      return false;
    }
  }
}
function _M0MPC13ref3Ref3RefGiE(x) {
  return new _M0TPC13ref3RefGiE(x);
}
function _M0MPC13ref3Ref3RefGORP311moonbitlang5async9js__async7PromiseGOsEE(x) {
  return new _M0TPC13ref3RefGORP311moonbitlang5async9js__async7PromiseGOsEE(x);
}
function _M0FPC13set8new__setGRP411moonbitlang5async8internal9coroutine9CoroutineE(capacity) {
  const capacity$2 = _M0MPC13int3Int20next__power__of__two(capacity);
  const _bind$3 = capacity$2 - 1 | 0;
  const _bind$4 = (Math.imul(capacity$2, 13) | 0) / 16 | 0;
  const _bind$5 = $make_array_len_and_init(capacity$2, undefined);
  const _bind$6 = undefined;
  return new _M0TPC13set3SetGRP411moonbitlang5async8internal9coroutine9CoroutineE(_bind$5, 0, capacity$2, _bind$3, _bind$4, _bind$6, -1);
}
function _M0FPC13set21capacity__for__length(length) {
  let capacity = _M0MPC13int3Int20next__power__of__two(length);
  const _p = capacity;
  if (length > ((Math.imul(_p, 13) | 0) / 16 | 0)) {
    capacity = Math.imul(capacity, 2) | 0;
  }
  return capacity;
}
function _M0MPC13set3Set20add__entry__to__tailGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, idx, entry) {
  const _bind$3 = self.tail;
  if (_bind$3 === -1) {
    self.head = entry;
  } else {
    const _tmp$2 = self.entries;
    const _p = _bind$3 >>> 0 < _tmp$2.length ? _tmp$2[_bind$3] : $oob();
    let _tmp$3;
    if (_p === undefined) {
      _tmp$3 = $panic();
    } else {
      const _p$2 = _p;
      _tmp$3 = _p$2;
    }
    _tmp$3.next = entry;
  }
  self.tail = idx;
  self.entries[idx] = entry;
  self.size = self.size + 1 | 0;
}
function _M0MPC13set3Set10set__entryGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, entry, new_idx) {
  const _bind$3 = entry.next;
  if (_bind$3 === undefined) {
    self.tail = new_idx;
  } else {
    const _Some = _bind$3;
    const _next = _Some;
    _next.prev = new_idx;
  }
  self.entries[new_idx] = entry;
}
function _M0MPC13set3Set10push__awayGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, idx, entry) {
  let _tmp$2 = entry.psl + 1 | 0;
  let _tmp$3 = idx + 1 & self.capacity_mask;
  let _tmp$4 = entry;
  while (true) {
    const psl = _tmp$2;
    const idx$2 = _tmp$3;
    const entry$2 = _tmp$4;
    const _bind$3 = self.entries[idx$2];
    if (_bind$3 === undefined) {
      entry$2.psl = psl;
      _M0MPC13set3Set10set__entryGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, entry$2, idx$2);
      return;
    } else {
      const _Some = _bind$3;
      const _curr_entry = _Some;
      if (psl > _curr_entry.psl) {
        entry$2.psl = psl;
        _M0MPC13set3Set10set__entryGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, entry$2, idx$2);
        _tmp$2 = _curr_entry.psl + 1 | 0;
        _tmp$3 = idx$2 + 1 & self.capacity_mask;
        _tmp$4 = _curr_entry;
        continue;
      } else {
        _tmp$2 = psl + 1 | 0;
        _tmp$3 = idx$2 + 1 & self.capacity_mask;
        continue;
      }
    }
  }
}
function _M0MPC13set3Set20rehash__place__entryGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, outer) {
  const hash = outer.hash;
  let _tmp$2 = 0;
  let _tmp$3 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp$2;
    const idx = _tmp$3;
    const _bind$3 = self.entries[idx];
    if (_bind$3 === undefined) {
      outer.psl = psl;
      outer.prev = self.tail;
      _M0MPC13set3Set20add__entry__to__tailGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, idx, outer);
      return undefined;
    } else {
      const _Some = _bind$3;
      const _curr = _Some;
      if (psl > _curr.psl) {
        _M0MPC13set3Set10push__awayGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, idx, _curr);
        outer.psl = psl;
        outer.prev = self.tail;
        _M0MPC13set3Set20add__entry__to__tailGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, idx, outer);
        return undefined;
      } else {
        _tmp$2 = psl + 1 | 0;
        _tmp$3 = idx + 1 & self.capacity_mask;
        continue;
      }
    }
  }
}
function _M0MPC13set3Set4growGRP411moonbitlang5async8internal9coroutine9CoroutineE(self) {
  const old_head = self.head;
  const new_capacity = self.capacity << 1;
  self.entries = $make_array_len_and_init(new_capacity, undefined);
  self.capacity = new_capacity;
  self.capacity_mask = new_capacity - 1 | 0;
  const _p = self.capacity;
  self.grow_at = (Math.imul(_p, 13) | 0) / 16 | 0;
  self.size = 0;
  self.head = undefined;
  self.tail = -1;
  let _tmp$2 = old_head;
  while (true) {
    const x = _tmp$2;
    if (x === undefined) {
      return;
    } else {
      const _Some = x;
      const _e = _Some;
      const next_in_chain = _e.next;
      _e.next = undefined;
      _M0MPC13set3Set20rehash__place__entryGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, _e);
      _tmp$2 = next_in_chain;
      continue;
    }
  }
}
function _M0MPC13set3Set15add__with__hashGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, key, hash) {
  if (self.size >= self.grow_at) {
    _M0MPC13set3Set4growGRP411moonbitlang5async8internal9coroutine9CoroutineE(self);
  }
  let idx;
  let psl;
  _L: {
    let _tmp$2 = 0;
    let _tmp$3 = hash & self.capacity_mask;
    while (true) {
      const psl$2 = _tmp$2;
      const idx$2 = _tmp$3;
      const _bind$3 = self.entries[idx$2];
      if (_bind$3 === undefined) {
        idx = idx$2;
        psl = psl$2;
        break _L;
      } else {
        const _Some = _bind$3;
        const _curr_entry = _Some;
        let _tmp$4;
        if (_curr_entry.hash === hash) {
          const _p = _curr_entry.key;
          _tmp$4 = _p.coro_id === key.coro_id;
        } else {
          _tmp$4 = false;
        }
        if (_tmp$4) {
          return undefined;
        }
        if (psl$2 > _curr_entry.psl) {
          _M0MPC13set3Set10push__awayGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, idx$2, _curr_entry);
          idx = idx$2;
          psl = psl$2;
          break _L;
        }
        _tmp$2 = psl$2 + 1 | 0;
        _tmp$3 = idx$2 + 1 & self.capacity_mask;
        continue;
      }
    }
  }
  const _bind$3 = self.tail;
  const _bind$4 = undefined;
  const entry = new _M0TPC13set5EntryGRP411moonbitlang5async8internal9coroutine9CoroutineE(_bind$3, _bind$4, psl, hash, key);
  _M0MPC13set3Set20add__entry__to__tailGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, idx, entry);
}
function _M0MPC13set3Set3addGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, key) {
  _M0MPC13set3Set15add__with__hashGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, key, _M0IP016_24default__implPB4Hash4hashGRP411moonbitlang5async8internal9coroutine9CoroutineE(key));
}
function _M0MPC13set3Set3SetGRP411moonbitlang5async8internal9coroutine9CoroutineE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPC13set21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    const _p = _M0FPC13set21capacity__for__length(length);
    capacity$2 = _capacity > _p ? _capacity : _p;
  }
  const m = _M0FPC13set8new__setGRP411moonbitlang5async8internal9coroutine9CoroutineE(capacity$2);
  const _bind$3 = arr.end - arr.start | 0;
  let _tmp$2 = 0;
  while (true) {
    const _ = _tmp$2;
    if (_ < _bind$3) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPC13set3Set3addGRP411moonbitlang5async8internal9coroutine9CoroutineE(m, e);
      _tmp$2 = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPC13set3Set13remove__entryGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, entry) {
  const _bind$3 = entry.prev;
  if (_bind$3 === -1) {
    self.head = entry.next;
  } else {
    const _tmp$2 = self.entries;
    const _p = _bind$3 >>> 0 < _tmp$2.length ? _tmp$2[_bind$3] : $oob();
    let _tmp$3;
    if (_p === undefined) {
      _tmp$3 = $panic();
    } else {
      const _p$2 = _p;
      _tmp$3 = _p$2;
    }
    _tmp$3.next = entry.next;
  }
  const _bind$4 = entry.next;
  if (_bind$4 === undefined) {
    self.tail = entry.prev;
    return;
  } else {
    const _Some = _bind$4;
    const _next = _Some;
    _next.prev = entry.prev;
    return;
  }
}
function _M0MPC13set3Set11shift__backGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, idx) {
  let _tmp$2 = idx;
  while (true) {
    const cur = _tmp$2;
    const next = cur + 1 & self.capacity_mask;
    _L: {
      const _bind$3 = self.entries[next];
      if (_bind$3 === undefined) {
        break _L;
      } else {
        const _Some = _bind$3;
        const _x = _Some;
        const _x$2 = _x.psl;
        if (_x$2 === 0) {
          break _L;
        } else {
          _x.psl = _x.psl - 1 | 0;
          _M0MPC13set3Set10set__entryGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, _x, cur);
          _tmp$2 = next;
          continue;
        }
      }
    }
    self.entries[cur] = undefined;
    return;
  }
}
function _M0MPC13set3Set6removeGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, key) {
  const hash = _M0IP016_24default__implPB4Hash4hashGRP411moonbitlang5async8internal9coroutine9CoroutineE(key);
  let _tmp$2 = 0;
  let _tmp$3 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp$2;
    const idx = _tmp$3;
    const _bind$3 = self.entries[idx];
    if (_bind$3 === undefined) {
      return;
    } else {
      const _Some = _bind$3;
      const _entry = _Some;
      let _tmp$4;
      if (_entry.hash === hash) {
        const _p = _entry.key;
        _tmp$4 = _p.coro_id === key.coro_id;
      } else {
        _tmp$4 = false;
      }
      if (_tmp$4) {
        _M0MPC13set3Set13remove__entryGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, _entry);
        _M0MPC13set3Set11shift__backGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, idx);
        self.size = self.size - 1 | 0;
        return;
      }
      if (i > _entry.psl) {
        return;
      }
      _tmp$2 = i + 1 | 0;
      _tmp$3 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPC13set3Set4iterGRP411moonbitlang5async8internal9coroutine9CoroutineE(self) {
  const curr_entry = new _M0TPB8MutLocalGORPC13set5EntryGRP411moonbitlang5async8internal9coroutine9CoroutineEE(self.head);
  const len = self.size;
  const remaining = new _M0TPB8MutLocalGiE(len);
  return _M0MPB4Iter3newGRP411moonbitlang5async8internal9coroutine9CoroutineE(() => {
    _L: {
      if (remaining.val > 0) {
        const _bind$3 = curr_entry.val;
        if (_bind$3 === undefined) {
          break _L;
        } else {
          const _Some = _bind$3;
          const _x = _Some;
          const _key = _x.key;
          const _next = _x.next;
          curr_entry.val = _next;
          remaining.val = remaining.val - 1 | 0;
          return _key;
        }
      } else {
        break _L;
      }
    }
    return undefined;
  }, len);
}
function _M0MPC15deque5Deque9as__viewsGRP411moonbitlang5async8internal9coroutine9CoroutineE(self) {
  if (self.len !== 0) {
    const _buf = self.buf;
    const _head = self.head;
    const _len = self.len;
    const cap = _buf.length;
    const head_len = cap - _head | 0;
    if (head_len >= _len) {
      const _tmp$2 = _M0MPB18UninitializedArray21clamped__view_2einnerGRP411moonbitlang5async8internal9coroutine9CoroutineE(_buf, _head, _head + _len | 0);
      const _bind$3 = [];
      return { _0: _tmp$2, _1: new _M0TPB9ArrayViewGRP411moonbitlang5async8internal9coroutine9CoroutineE(_bind$3, 0, 0) };
    } else {
      return { _0: _M0MPB18UninitializedArray21clamped__view_2einnerGRP411moonbitlang5async8internal9coroutine9CoroutineE(_buf, _head, cap), _1: _M0MPB18UninitializedArray21clamped__view_2einnerGRP411moonbitlang5async8internal9coroutine9CoroutineE(_buf, 0, _len - head_len | 0) };
    }
  } else {
    const _bind$3 = [];
    const _tmp$2 = new _M0TPB9ArrayViewGRP411moonbitlang5async8internal9coroutine9CoroutineE(_bind$3, 0, 0);
    const _bind$4 = [];
    return { _0: _tmp$2, _1: new _M0TPB9ArrayViewGRP411moonbitlang5async8internal9coroutine9CoroutineE(_bind$4, 0, 0) };
  }
}
function _M0MPC15deque5Deque27unsafe__make__and__blit__toGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, allocate_len, dst_offset) {
  if (self.len !== 0) {
    const _bind$3 = _M0MPC15deque5Deque9as__viewsGRP411moonbitlang5async8internal9coroutine9CoroutineE(self);
    const _front = _bind$3._0;
    const _back = _bind$3._1;
    const dst = _M0MPB18UninitializedArray23make__and__blit_2einnerGRP411moonbitlang5async8internal9coroutine9CoroutineE(self.buf, allocate_len, _front.end - _front.start | 0, _front.start, dst_offset);
    _M0MPB18UninitializedArray12unsafe__blitGRP411moonbitlang5async8internal9coroutine9CoroutineE(dst, dst_offset + (_front.end - _front.start | 0) | 0, self.buf, _back.start, _back.end - _back.start | 0);
    return dst;
  } else {
    return new Array(allocate_len);
  }
}
function _M0MPC15deque5Deque5DequeGRP411moonbitlang5async8internal9coroutine9CoroutineE(arr, capacity) {
  const len = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = len;
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _capacity > len ? _capacity : len;
  }
  const buf = new Array(capacity$2);
  const _bind$3 = arr.end - arr.start | 0;
  let _tmp$2 = 0;
  while (true) {
    const i = _tmp$2;
    if (i < _bind$3) {
      const x = arr.buf[arr.start + i | 0];
      if (i >>> 0 < buf.length) {
        buf[i] = x;
      } else {
        $oob();
      }
      _tmp$2 = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return new _M0TPC15deque5DequeGRP411moonbitlang5async8internal9coroutine9CoroutineE(buf, len, 0);
}
function _M0MPC15deque5Deque7reallocGRP411moonbitlang5async8internal9coroutine9CoroutineE(self) {
  const _p = self.buf;
  const old_cap = _p.length;
  const new_cap = old_cap === 0 ? 8 : Math.imul(old_cap, 2) | 0;
  const new_buf = _M0MPC15deque5Deque27unsafe__make__and__blit__toGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, new_cap, 0);
  self.head = 0;
  self.buf = new_buf;
}
function _M0MPC15deque5Deque10push__backGRP411moonbitlang5async8internal9coroutine9CoroutineE(self, value) {
  const _tmp$2 = self.len;
  const _p = self.buf;
  if (_tmp$2 === _p.length) {
    _M0MPC15deque5Deque7reallocGRP411moonbitlang5async8internal9coroutine9CoroutineE(self);
  }
  const _p$2 = self.buf;
  const cap = _p$2.length;
  const write_idx = (self.head + self.len | 0) % cap | 0;
  const _tmp$3 = self.buf;
  if (write_idx >>> 0 < _tmp$3.length) {
    _tmp$3[write_idx] = value;
  } else {
    $oob();
  }
  self.len = self.len + 1 | 0;
}
function _M0MPC15deque5Deque10pop__frontGRP411moonbitlang5async8internal9coroutine9CoroutineE(self) {
  if (self.len > 0) {
    const _tmp$2 = self.buf;
    const _tmp$3 = self.head;
    const value = _tmp$3 >>> 0 < _tmp$2.length ? _tmp$2[_tmp$3] : $oob();
    const _p = self.buf;
    const cap = _p.length;
    self.head = (self.head + 1 | 0) % cap | 0;
    self.len = self.len - 1 | 0;
    return value;
  } else {
    return undefined;
  }
}
function _M0FP411moonbitlang5async8internal9coroutine18current__coroutine() {
  const _p = _M0FP411moonbitlang5async8internal9coroutine9scheduler.curr_coro;
  if (_p === undefined) {
    return $panic();
  } else {
    const _p$2 = _p;
    return _p$2;
  }
}
function _M0FP411moonbitlang5async8internal9coroutine29has__immediately__ready__task() {
  const _p = _M0FP411moonbitlang5async8internal9coroutine9scheduler.run_later;
  return !(_p.len === 0);
}
function _M0FP411moonbitlang5async8internal9coroutine10reschedule() {
  const _p = _M0FP411moonbitlang5async8internal9coroutine9scheduler.run_later;
  const n = _p.len;
  let _tmp$2 = 0;
  while (true) {
    const _ = _tmp$2;
    if (_ < n) {
      const _bind$3 = _M0MPC15deque5Deque10pop__frontGRP411moonbitlang5async8internal9coroutine9CoroutineE(_M0FP411moonbitlang5async8internal9coroutine9scheduler.run_later);
      if (_bind$3 === undefined) {
        return;
      } else {
        const _Some = _bind$3;
        const _coro = _Some;
        _coro.ready = false;
        const _bind$4 = _coro.state;
        if (_bind$4.$tag === 4) {
          const _Suspend = _bind$4;
          const _cont = _Suspend._0;
          _coro.state = _M0DTP411moonbitlang5async8internal9coroutine5State7Running__;
          const last_coro = _M0FP411moonbitlang5async8internal9coroutine9scheduler.curr_coro;
          _M0FP411moonbitlang5async8internal9coroutine9scheduler.curr_coro = _coro;
          if (_coro.cancelled && !_coro.shielded) {
            _cont(1);
          } else {
            _cont(0);
          }
          _M0FP411moonbitlang5async8internal9coroutine9scheduler.curr_coro = last_coro;
        }
      }
      _tmp$2 = _ + 1 | 0;
      continue;
    } else {
      return;
    }
  }
}
function _M0IP411moonbitlang5async8internal9coroutine9CoroutinePB4Hash13hash__combine(self, hasher) {
  _M0IPC13int3IntPB4Hash13hash__combine(self.coro_id, hasher);
}
function _M0MP411moonbitlang5async8internal9coroutine9Coroutine4wake(self) {
  if (!self.ready) {
    self.ready = true;
    _M0MPC15deque5Deque10push__backGRP411moonbitlang5async8internal9coroutine9CoroutineE(_M0FP411moonbitlang5async8internal9coroutine9scheduler.run_later, self);
    return;
  } else {
    return;
  }
}
function _M0MP411moonbitlang5async8internal9coroutine9Coroutine6cancel(self) {
  self.cancelled = true;
  if (!self.shielded) {
    _M0MP411moonbitlang5async8internal9coroutine9Coroutine4wake(self);
    return;
  } else {
    return;
  }
}
function _M0FP411moonbitlang5async8internal9coroutine22suspend__check__cancel(_cont, _err_cont) {
  const _bind$3 = _M0FP411moonbitlang5async8internal9coroutine9scheduler.curr_coro;
  if (_bind$3 === undefined) {
    return new _M0DTPC16result6ResultGORP411moonbitlang5async8internal9coroutine13SuspendResultRPB9CancelledE2Ok($panic());
  } else {
    const _Some = _bind$3;
    const _coro = _Some;
    if (_coro.cancelled && !_coro.shielded) {
      return new _M0DTPC16result6ResultGORP411moonbitlang5async8internal9coroutine13SuspendResultRPB9CancelledE2Ok(_M0FP411moonbitlang5async8internal9coroutine22suspend__check__cancelN6constrS374);
    }
    const _bind$4 = _coro.state;
    if (_bind$4.$tag === 3) {
      _coro.state = new _M0DTP411moonbitlang5async8internal9coroutine5State7Suspend(_cont);
    } else {
      $panic();
    }
    return new _M0DTPC16result6ResultGORP411moonbitlang5async8internal9coroutine13SuspendResultRPB9CancelledE2Ok(undefined);
  }
}
function _M0FP411moonbitlang5async8internal9coroutine7suspendN16_2aasync__driverS232(_state) {
  const _State_0 = _state;
  const _cont_param = _State_0._0;
  if (_cont_param === 0) {
    return new _M0DTPC16result6ResultGOuRPB9CancelledE2Ok(undefined);
  } else {
    return new _M0DTPC16result6ResultGOuRPB9CancelledE3Err(_M0DTPC15error5Error52moonbitlang_2fcore_2fbuiltin_2eCancelled_2eCancelled__);
  }
}
function _M0FP411moonbitlang5async8internal9coroutine7suspend(_cont, _err_cont) {
  const _bind$3 = _M0FP411moonbitlang5async8internal9coroutine22suspend__check__cancel((_cont_param) => {
    let _err;
    _L: {
      const _bind$4 = _M0FP411moonbitlang5async8internal9coroutine7suspendN16_2aasync__driverS232(new _M0DTP411moonbitlang5async8internal9coroutine55_24moonbitlang_2fasync_2finternal_2fcoroutine_2esuspendL5State8State__0(_cont_param));
      let _bind$5;
      if (_bind$4.$tag === 1) {
        const _ok = _bind$4;
        _bind$5 = _ok._0;
      } else {
        const _err$2 = _bind$4;
        _err = _err$2._0;
        break _L;
      }
      if (_bind$5 === -1) {
        return;
      } else {
        const _Some = _bind$5;
        const _payload = _Some;
        _cont(_payload);
        return;
      }
    }
    _err_cont(_err);
  }, _err_cont);
  let _bind$4;
  if (_bind$3.$tag === 1) {
    const _ok = _bind$3;
    _bind$4 = _ok._0;
  } else {
    return _bind$3;
  }
  if (_bind$4 === undefined) {
    return new _M0DTPC16result6ResultGOuRPB9CancelledE2Ok(-1);
  } else {
    const _Some = _bind$4;
    const _payload = _Some;
    return _M0FP411moonbitlang5async8internal9coroutine7suspendN16_2aasync__driverS232(new _M0DTP411moonbitlang5async8internal9coroutine55_24moonbitlang_2fasync_2finternal_2fcoroutine_2esuspendL5State8State__0(_payload));
  }
}
function _M0FP411moonbitlang5async8internal9coroutine5spawnN7_2acontS262(_param) {}
function _M0FP411moonbitlang5async8internal9coroutine5spawnN16_2aasync__driverS263(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _State_0 = _state$2;
        const coro = _State_0._1;
        const _it = _M0MPC13set3Set4iterGRP411moonbitlang5async8internal9coroutine9CoroutineE(coro.downstream);
        while (true) {
          const _bind$3 = _M0MPB4Iter4nextGRP411moonbitlang5async8internal9coroutine9CoroutineE(_it);
          if (_bind$3 === undefined) {
            break;
          } else {
            const _Some = _bind$3;
            const _coro = _Some;
            _M0MP411moonbitlang5async8internal9coroutine9Coroutine4wake(_coro);
            continue;
          }
        }
        return _M0MPC13set3Set6removeGRP411moonbitlang5async8internal9coroutine9CoroutineE(_M0FP411moonbitlang5async8internal9coroutine9scheduler.all_coros, coro);
      }
      case 1: {
        const _$42$try$47$93 = _state$2;
        const coro$2 = _$42$try$47$93._1;
        const _try_err = _$42$try$47$93._0;
        coro$2.state = new _M0DTP411moonbitlang5async8internal9coroutine5State4Fail(_try_err);
        _tmp$2 = new _M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State8State__0(undefined, coro$2);
        continue _L;
      }
      case 2: {
        const _State_2 = _state$2;
        const coro$3 = _State_2._1;
        const _bind$3 = coro$3.state;
        if (_bind$3.$tag === 3) {
          coro$3.state = _M0DTP411moonbitlang5async8internal9coroutine5State4Done__;
          _tmp$2 = new _M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State8State__0(undefined, coro$3);
          continue _L;
        } else {
          _tmp$2 = new _M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State8State__0(undefined, coro$3);
          continue _L;
        }
      }
      default: {
        const _$42$cancellation_handler$47$96 = _state$2;
        const coro$4 = _$42$cancellation_handler$47$96._1;
        const _err = _$42$cancellation_handler$47$96._0;
        if (_err.$tag === 1) {
          coro$4.state = _M0DTP411moonbitlang5async8internal9coroutine5State9Cancelled__;
          _tmp$2 = new _M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State8State__2(undefined, coro$4);
          continue _L;
        } else {
          _tmp$2 = new _M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State11_2atry_2f93(_err, coro$4);
          continue _L;
        }
      }
    }
  }
}
function _M0FP411moonbitlang5async8internal9coroutine5spawn(f, loc) {
  _M0FP411moonbitlang5async8internal9coroutine9scheduler.coro_id = _M0FP411moonbitlang5async8internal9coroutine9scheduler.coro_id + 1 | 0;
  const _bind$3 = _M0DTP411moonbitlang5async8internal9coroutine5State7Running__;
  const _bind$4 = [];
  const _bind$5 = _M0MPC13set3Set3SetGRP411moonbitlang5async8internal9coroutine9CoroutineE(new _M0TPB9ArrayViewGRP411moonbitlang5async8internal9coroutine9CoroutineE(_bind$4, 0, 0), undefined);
  const _bind$6 = _M0FP411moonbitlang5async8internal9coroutine9scheduler.coro_id;
  const coro = new _M0TP411moonbitlang5async8internal9coroutine9Coroutine(_bind$6, _bind$3, false, false, true, _bind$5, loc);
  const run = (_discard_) => {
    let _err;
    _L: {
      _L$2: {
        const _bind$7 = f((_cont_param) => {
          const _bind$8 = _M0FP411moonbitlang5async8internal9coroutine5spawnN16_2aasync__driverS263(new _M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State8State__2(_cont_param, coro));
          if (_bind$8 === -1) {
            return;
          } else {
            const _Some = _bind$8;
            const _payload = _Some;
            _M0FP411moonbitlang5async8internal9coroutine5spawnN7_2acontS262(_payload);
            return;
          }
        }, (_cont_param) => {
          const _bind$8 = _M0FP411moonbitlang5async8internal9coroutine5spawnN16_2aasync__driverS263(new _M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State29_2acancellation__handler_2f96(_cont_param, coro));
          if (_bind$8 === -1) {
            return;
          } else {
            const _Some = _bind$8;
            const _payload = _Some;
            _M0FP411moonbitlang5async8internal9coroutine5spawnN7_2acontS262(_payload);
            return;
          }
        });
        let _bind$8;
        if (_bind$7.$tag === 1) {
          const _ok = _bind$7;
          _bind$8 = _ok._0;
        } else {
          const _err$2 = _bind$7;
          _err = _err$2._0;
          break _L$2;
        }
        if (_bind$8 === -1) {
        } else {
          const _Some = _bind$8;
          const _payload = _Some;
          _M0FP411moonbitlang5async8internal9coroutine5spawnN16_2aasync__driverS263(new _M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State8State__2(_payload, coro));
        }
        break _L;
      }
      _M0FP411moonbitlang5async8internal9coroutine5spawnN16_2aasync__driverS263(new _M0DTP411moonbitlang5async8internal9coroutine79_24moonbitlang_2fasync_2finternal_2fcoroutine_2espawn_2erun_2f18_2elambda_2f261L5State29_2acancellation__handler_2f96(_err, coro));
    }
  };
  coro.state = new _M0DTP411moonbitlang5async8internal9coroutine5State7Suspend(run);
  _M0MPC15deque5Deque10push__backGRP411moonbitlang5async8internal9coroutine9CoroutineE(_M0FP411moonbitlang5async8internal9coroutine9scheduler.run_later, coro);
  _M0MPC13set3Set3addGRP411moonbitlang5async8internal9coroutine9CoroutineE(_M0FP411moonbitlang5async8internal9coroutine9scheduler.all_coros, coro);
  return coro;
}
function _M0FP411moonbitlang5async8internal9coroutine21protect__from__cancelN16_2aasync__driverS316GuE(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _$42$cancellation_handler$47$162 = _state$2;
        const _err = _$42$cancellation_handler$47$162._0;
        if (_err.$tag === 1) {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok($panic());
        } else {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE3Err(_err);
        }
      }
      case 1: {
        const _$42$defer_try$47$157 = _state$2;
        const _defer = _$42$defer_try$47$157._1;
        const _err$2 = _$42$defer_try$47$157._0;
        _defer();
        _tmp$2 = new _M0DTP411moonbitlang5async8internal9coroutine69_24moonbitlang_2fasync_2finternal_2fcoroutine_2eprotect__from__cancelL5StateGuE30_2acancellation__handler_2f162(_err$2);
        continue _L;
      }
      default: {
        const _State_2 = _state$2;
        const _defer$2 = _State_2._1;
        const _cont_param = _State_2._0;
        _defer$2();
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(_cont_param);
      }
    }
  }
}
function _M0FP411moonbitlang5async8internal9coroutine21protect__from__cancelGuE(f, _cont, _err_cont) {
  const _bind$3 = _M0FP411moonbitlang5async8internal9coroutine9scheduler.curr_coro;
  if (_bind$3 === undefined) {
    return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok($panic());
  } else {
    const _Some = _bind$3;
    const _coro = _Some;
    if (_coro.shielded) {
      let _err;
      _L: {
        const _bind$4 = f(_cont, (_cont_param) => {
          let _err$2;
          _L$2: {
            const _bind$5 = _M0FP411moonbitlang5async8internal9coroutine21protect__from__cancelN16_2aasync__driverS316GuE(new _M0DTP411moonbitlang5async8internal9coroutine69_24moonbitlang_2fasync_2finternal_2fcoroutine_2eprotect__from__cancelL5StateGuE30_2acancellation__handler_2f162(_cont_param));
            let _bind$6;
            if (_bind$5.$tag === 1) {
              const _ok = _bind$5;
              _bind$6 = _ok._0;
            } else {
              const _err$3 = _bind$5;
              _err$2 = _err$3._0;
              break _L$2;
            }
            if (_bind$6 === -1) {
              return;
            } else {
              const _Some$2 = _bind$6;
              const _payload = _Some$2;
              _cont(_payload);
              return;
            }
          }
          _err_cont(_err$2);
        });
        let _bind$5;
        if (_bind$4.$tag === 1) {
          const _ok = _bind$4;
          _bind$5 = _ok._0;
        } else {
          const _err$2 = _bind$4;
          _err = _err$2._0;
          break _L;
        }
        if (_bind$5 === -1) {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        } else {
          const _Some$2 = _bind$5;
          const _payload = _Some$2;
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(_payload);
        }
      }
      return _M0FP411moonbitlang5async8internal9coroutine21protect__from__cancelN16_2aasync__driverS316GuE(new _M0DTP411moonbitlang5async8internal9coroutine69_24moonbitlang_2fasync_2finternal_2fcoroutine_2eprotect__from__cancelL5StateGuE30_2acancellation__handler_2f162(_err));
    } else {
      _coro.shielded = true;
      const _defer = () => {
        _coro.shielded = false;
      };
      let _err;
      _L: {
        const _bind$4 = f((_cont_param) => {
          let _err$2;
          _L$2: {
            const _bind$5 = _M0FP411moonbitlang5async8internal9coroutine21protect__from__cancelN16_2aasync__driverS316GuE(new _M0DTP411moonbitlang5async8internal9coroutine69_24moonbitlang_2fasync_2finternal_2fcoroutine_2eprotect__from__cancelL5StateGuE8State__2(_cont_param, _defer));
            let _bind$6;
            if (_bind$5.$tag === 1) {
              const _ok = _bind$5;
              _bind$6 = _ok._0;
            } else {
              const _err$3 = _bind$5;
              _err$2 = _err$3._0;
              break _L$2;
            }
            if (_bind$6 === -1) {
              return;
            } else {
              const _Some$2 = _bind$6;
              const _payload = _Some$2;
              _cont(_payload);
              return;
            }
          }
          _err_cont(_err$2);
        }, (_cont_param) => {
          let _err$2;
          _L$2: {
            const _bind$5 = _M0FP411moonbitlang5async8internal9coroutine21protect__from__cancelN16_2aasync__driverS316GuE(new _M0DTP411moonbitlang5async8internal9coroutine69_24moonbitlang_2fasync_2finternal_2fcoroutine_2eprotect__from__cancelL5StateGuE19_2adefer__try_2f157(_cont_param, _defer));
            let _bind$6;
            if (_bind$5.$tag === 1) {
              const _ok = _bind$5;
              _bind$6 = _ok._0;
            } else {
              const _err$3 = _bind$5;
              _err$2 = _err$3._0;
              break _L$2;
            }
            if (_bind$6 === -1) {
              return;
            } else {
              const _Some$2 = _bind$6;
              const _payload = _Some$2;
              _cont(_payload);
              return;
            }
          }
          _err_cont(_err$2);
        });
        let _bind$5;
        if (_bind$4.$tag === 1) {
          const _ok = _bind$4;
          _bind$5 = _ok._0;
        } else {
          const _err$2 = _bind$4;
          _err = _err$2._0;
          break _L;
        }
        if (_bind$5 === -1) {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        } else {
          const _Some$2 = _bind$5;
          const _payload = _Some$2;
          return _M0FP411moonbitlang5async8internal9coroutine21protect__from__cancelN16_2aasync__driverS316GuE(new _M0DTP411moonbitlang5async8internal9coroutine69_24moonbitlang_2fasync_2finternal_2fcoroutine_2eprotect__from__cancelL5StateGuE8State__2(_payload, _defer));
        }
      }
      return _M0FP411moonbitlang5async8internal9coroutine21protect__from__cancelN16_2aasync__driverS316GuE(new _M0DTP411moonbitlang5async8internal9coroutine69_24moonbitlang_2fasync_2finternal_2fcoroutine_2eprotect__from__cancelL5StateGuE19_2adefer__try_2f157(_err, _defer));
    }
  }
}
function _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationN16_2aasync__driverS349GuE(_state) {
  if (_state.$tag === 0) {
    const _$42$cancellation_handler$47$171 = _state;
    const _err = _$42$cancellation_handler$47$171._0;
    if (_err.$tag === 1) {
      return new _M0DTPC16result6ResultGOOuRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOuE4Some(-1));
    } else {
      return new _M0DTPC16result6ResultGOOuRPC15error5ErrorE3Err(_err);
    }
  } else {
    const _State_1 = _state;
    const _cont_param = _State_1._0;
    return new _M0DTPC16result6ResultGOOuRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOuE4Some(_cont_param));
  }
}
function _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationN16_2aasync__driverS349GRP46f4ah6o3dsh7browser2sw10SwResponseE(_state) {
  if (_state.$tag === 0) {
    const _$42$cancellation_handler$47$171 = _state;
    const _err = _$42$cancellation_handler$47$171._0;
    if (_err.$tag === 1) {
      return new _M0DTPC16result6ResultGOORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4None__);
    } else {
      return new _M0DTPC16result6ResultGOORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE3Err(_err);
    }
  } else {
    const _State_1 = _state;
    const _cont_param = _State_1._0;
    return new _M0DTPC16result6ResultGOORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4Some(_cont_param));
  }
}
function _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationN16_2aasync__driverS349GbE(_state) {
  if (_state.$tag === 0) {
    const _$42$cancellation_handler$47$171 = _state;
    const _err = _$42$cancellation_handler$47$171._0;
    if (_err.$tag === 1) {
      return new _M0DTPC16result6ResultGOObRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGObE4Some(-1));
    } else {
      return new _M0DTPC16result6ResultGOObRPC15error5ErrorE3Err(_err);
    }
  } else {
    const _State_1 = _state;
    const _cont_param = _State_1._0;
    return new _M0DTPC16result6ResultGOObRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGObE4Some(_cont_param));
  }
}
function _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationGuE(f, _cont, _err_cont) {
  let _err;
  _L: {
    const _bind$3 = f((_cont_param) => {
      let _err$2;
      _L$2: {
        const _bind$4 = _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationN16_2aasync__driverS349GuE(new _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGuE8State__1(_cont_param));
        let _tmp$2;
        if (_bind$4.$tag === 1) {
          const _ok = _bind$4;
          _tmp$2 = _ok._0;
        } else {
          const _err$3 = _bind$4;
          _err$2 = _err$3._0;
          break _L$2;
        }
        const _tmp$3 = _tmp$2;
        if (_tmp$3.$tag === 1) {
          const _Some = _tmp$3;
          const _payload = _Some._0;
          _cont(_payload);
          return;
        } else {
          return;
        }
      }
      _err_cont(_err$2);
    }, (_cont_param) => {
      let _err$2;
      _L$2: {
        const _bind$4 = _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationN16_2aasync__driverS349GuE(new _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGuE30_2acancellation__handler_2f171(_cont_param));
        let _tmp$2;
        if (_bind$4.$tag === 1) {
          const _ok = _bind$4;
          _tmp$2 = _ok._0;
        } else {
          const _err$3 = _bind$4;
          _err$2 = _err$3._0;
          break _L$2;
        }
        const _tmp$3 = _tmp$2;
        if (_tmp$3.$tag === 1) {
          const _Some = _tmp$3;
          const _payload = _Some._0;
          _cont(_payload);
          return;
        } else {
          return;
        }
      }
      _err_cont(_err$2);
    });
    let _bind$4;
    if (_bind$3.$tag === 1) {
      const _ok = _bind$3;
      _bind$4 = _ok._0;
    } else {
      const _err$2 = _bind$3;
      _err = _err$2._0;
      break _L;
    }
    if (_bind$4 === -1) {
      return new _M0DTPC16result6ResultGOOuRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOuE4None__);
    } else {
      const _Some = _bind$4;
      const _payload = _Some;
      return _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationN16_2aasync__driverS349GuE(new _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGuE8State__1(_payload));
    }
  }
  return _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationN16_2aasync__driverS349GuE(new _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGuE30_2acancellation__handler_2f171(_err));
}
function _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationGRP46f4ah6o3dsh7browser2sw10SwResponseE(f, _cont, _err_cont) {
  let _err;
  _L: {
    const _bind$3 = f((_cont_param) => {
      let _err$2;
      _L$2: {
        const _bind$4 = _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationN16_2aasync__driverS349GRP46f4ah6o3dsh7browser2sw10SwResponseE(new _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE8State__1(_cont_param));
        let _bind$5;
        if (_bind$4.$tag === 1) {
          const _ok = _bind$4;
          _bind$5 = _ok._0;
        } else {
          const _err$3 = _bind$4;
          _err$2 = _err$3._0;
          break _L$2;
        }
        if (_bind$5 === undefined) {
          return;
        } else {
          const _Some = _bind$5;
          const _payload = _Some;
          _cont(_payload);
          return;
        }
      }
      _err_cont(_err$2);
    }, (_cont_param) => {
      let _err$2;
      _L$2: {
        const _bind$4 = _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationN16_2aasync__driverS349GRP46f4ah6o3dsh7browser2sw10SwResponseE(new _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE30_2acancellation__handler_2f171(_cont_param));
        let _bind$5;
        if (_bind$4.$tag === 1) {
          const _ok = _bind$4;
          _bind$5 = _ok._0;
        } else {
          const _err$3 = _bind$4;
          _err$2 = _err$3._0;
          break _L$2;
        }
        if (_bind$5 === undefined) {
          return;
        } else {
          const _Some = _bind$5;
          const _payload = _Some;
          _cont(_payload);
          return;
        }
      }
      _err_cont(_err$2);
    });
    let _tmp$2;
    if (_bind$3.$tag === 1) {
      const _ok = _bind$3;
      _tmp$2 = _ok._0;
    } else {
      const _err$2 = _bind$3;
      _err = _err$2._0;
      break _L;
    }
    const _tmp$3 = _tmp$2;
    if (_tmp$3.$tag === 1) {
      const _Some = _tmp$3;
      const _payload = _Some._0;
      return _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationN16_2aasync__driverS349GRP46f4ah6o3dsh7browser2sw10SwResponseE(new _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE8State__1(_payload));
    } else {
      return new _M0DTPC16result6ResultGOORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok(undefined);
    }
  }
  return _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationN16_2aasync__driverS349GRP46f4ah6o3dsh7browser2sw10SwResponseE(new _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE30_2acancellation__handler_2f171(_err));
}
function _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationGbE(f, _cont, _err_cont) {
  let _err;
  _L: {
    const _bind$3 = f((_cont_param) => {
      let _err$2;
      _L$2: {
        const _bind$4 = _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationN16_2aasync__driverS349GbE(new _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGbE8State__1(_cont_param));
        let _tmp$2;
        if (_bind$4.$tag === 1) {
          const _ok = _bind$4;
          _tmp$2 = _ok._0;
        } else {
          const _err$3 = _bind$4;
          _err$2 = _err$3._0;
          break _L$2;
        }
        const _tmp$3 = _tmp$2;
        if (_tmp$3.$tag === 1) {
          const _Some = _tmp$3;
          const _payload = _Some._0;
          _cont(_payload);
          return;
        } else {
          return;
        }
      }
      _err_cont(_err$2);
    }, (_cont_param) => {
      let _err$2;
      _L$2: {
        const _bind$4 = _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationN16_2aasync__driverS349GbE(new _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGbE30_2acancellation__handler_2f171(_cont_param));
        let _tmp$2;
        if (_bind$4.$tag === 1) {
          const _ok = _bind$4;
          _tmp$2 = _ok._0;
        } else {
          const _err$3 = _bind$4;
          _err$2 = _err$3._0;
          break _L$2;
        }
        const _tmp$3 = _tmp$2;
        if (_tmp$3.$tag === 1) {
          const _Some = _tmp$3;
          const _payload = _Some._0;
          _cont(_payload);
          return;
        } else {
          return;
        }
      }
      _err_cont(_err$2);
    });
    let _bind$4;
    if (_bind$3.$tag === 1) {
      const _ok = _bind$3;
      _bind$4 = _ok._0;
    } else {
      const _err$2 = _bind$3;
      _err = _err$2._0;
      break _L;
    }
    if (_bind$4 === -1) {
      return new _M0DTPC16result6ResultGOObRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGObE4None__);
    } else {
      const _Some = _bind$4;
      const _payload = _Some;
      return _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationN16_2aasync__driverS349GbE(new _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGbE8State__1(_payload));
    }
  }
  return _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationN16_2aasync__driverS349GbE(new _M0DTP411moonbitlang5async8internal9coroutine68_24moonbitlang_2fasync_2finternal_2fcoroutine_2ehandle__cancellationL5StateGbE30_2acancellation__handler_2f171(_err));
}
function _M0FP411moonbitlang5async8internal11event__loop10reschedule() {
  const _p = _M0FP411moonbitlang5async8internal9coroutine9scheduler.all_coros;
  if (!(_p.size === 0)) {
    _M0FP411moonbitlang5async8internal9coroutine10reschedule();
    if (_M0FP411moonbitlang5async8internal9coroutine29has__immediately__ready__task()) {
      _M0FP411moonbitlang5async8internal11event__loop12set__timeout(0, _M0FP411moonbitlang5async8internal11event__loop10reschedule);
      return;
    } else {
      return;
    }
  } else {
    return;
  }
}
function _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GbE(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _$42$defer_try$47$90 = _state$2;
        const _defer = _$42$defer_try$47$90._1;
        const _err = _$42$defer_try$47$90._0;
        _defer();
        return new _M0DTPC16result6ResultGObRPC15error5ErrorE3Err(_err);
      }
      case 1: {
        const _State_1 = _state$2;
        const _defer$2 = _State_1._2;
        const waiter = _State_1._1;
        const _bind$3 = waiter.err;
        let _defer_result;
        if (_bind$3 === undefined) {
          const _p = waiter.ret;
          _defer_result = _p === -1 ? $panic() : _p;
        } else {
          const _Some = _bind$3;
          const _err$2 = _Some;
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE18_2adefer__try_2f90(_err$2, _defer$2);
          continue _L;
        }
        _defer$2();
        return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(_defer_result);
      }
      default: {
        const _$42$defer_try$47$91 = _state$2;
        const _defer$3 = _$42$defer_try$47$91._2;
        const controller = _$42$defer_try$47$91._1;
        const _err$2 = _$42$defer_try$47$91._0;
        _M0MP311moonbitlang5async9js__async15AbortController5abort(controller);
        _tmp$2 = new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE18_2adefer__try_2f90(_err$2, _defer$3);
        continue _L;
      }
    }
  }
}
function _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GuE(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _$42$defer_try$47$90 = _state$2;
        const _defer = _$42$defer_try$47$90._1;
        const _err = _$42$defer_try$47$90._0;
        _defer();
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE3Err(_err);
      }
      case 1: {
        const _State_1 = _state$2;
        const _defer$2 = _State_1._2;
        const waiter = _State_1._1;
        const _bind$3 = waiter.err;
        let _defer_result;
        if (_bind$3 === undefined) {
          const _p = waiter.ret;
          if (_p === -1) {
            $panic();
          }
        } else {
          const _Some = _bind$3;
          const _err$2 = _Some;
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE18_2adefer__try_2f90(_err$2, _defer$2);
          continue _L;
        }
        _defer$2();
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(_defer_result);
      }
      default: {
        const _$42$defer_try$47$91 = _state$2;
        const _defer$3 = _$42$defer_try$47$91._2;
        const controller = _$42$defer_try$47$91._1;
        const _err$2 = _$42$defer_try$47$91._0;
        _M0MP311moonbitlang5async9js__async15AbortController5abort(controller);
        _tmp$2 = new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE18_2adefer__try_2f90(_err$2, _defer$3);
        continue _L;
      }
    }
  }
}
function _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GRPB5ArrayGsEE(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _$42$defer_try$47$90 = _state$2;
        const _defer = _$42$defer_try$47$90._1;
        const _err = _$42$defer_try$47$90._0;
        _defer();
        return new _M0DTPC16result6ResultGORPB5ArrayGsERPC15error5ErrorE3Err(_err);
      }
      case 1: {
        const _State_1 = _state$2;
        const _defer$2 = _State_1._2;
        const waiter = _State_1._1;
        const _bind$3 = waiter.err;
        let _defer_result;
        if (_bind$3 === undefined) {
          _defer_result = _M0MPC16option6Option6unwrapGRPB5ArrayGsEE(waiter.ret);
        } else {
          const _Some = _bind$3;
          const _err$2 = _Some;
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE18_2adefer__try_2f90(_err$2, _defer$2);
          continue _L;
        }
        _defer$2();
        return new _M0DTPC16result6ResultGORPB5ArrayGsERPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGRPB5ArrayGsEE4Some(_defer_result));
      }
      default: {
        const _$42$defer_try$47$91 = _state$2;
        const _defer$3 = _$42$defer_try$47$91._2;
        const controller = _$42$defer_try$47$91._1;
        const _err$2 = _$42$defer_try$47$91._0;
        _M0MP311moonbitlang5async9js__async15AbortController5abort(controller);
        _tmp$2 = new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE18_2adefer__try_2f90(_err$2, _defer$3);
        continue _L;
      }
    }
  }
}
function _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GsE(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _$42$defer_try$47$90 = _state$2;
        const _defer = _$42$defer_try$47$90._1;
        const _err = _$42$defer_try$47$90._0;
        _defer();
        return new _M0DTPC16result6ResultGOsRPC15error5ErrorE3Err(_err);
      }
      case 1: {
        const _State_1 = _state$2;
        const _defer$2 = _State_1._2;
        const waiter = _State_1._1;
        const _bind$3 = waiter.err;
        let _defer_result;
        if (_bind$3 === undefined) {
          const _p = waiter.ret;
          if (_p === undefined) {
            _defer_result = $panic();
          } else {
            const _p$2 = _p;
            _defer_result = _p$2;
          }
        } else {
          const _Some = _bind$3;
          const _err$2 = _Some;
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE18_2adefer__try_2f90(_err$2, _defer$2);
          continue _L;
        }
        _defer$2();
        return new _M0DTPC16result6ResultGOsRPC15error5ErrorE2Ok(_defer_result);
      }
      default: {
        const _$42$defer_try$47$91 = _state$2;
        const _defer$3 = _$42$defer_try$47$91._2;
        const controller = _$42$defer_try$47$91._1;
        const _err$2 = _$42$defer_try$47$91._0;
        _M0MP311moonbitlang5async9js__async15AbortController5abort(controller);
        _tmp$2 = new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE18_2adefer__try_2f90(_err$2, _defer$3);
        continue _L;
      }
    }
  }
}
function _M0MP311moonbitlang5async9js__async7Promise4waitGbE(promise, abort_controller, _cont, _err_cont) {
  const waiter = new _M0TP311moonbitlang5async9js__async13PromiseWaiterGbE(_M0FP411moonbitlang5async8internal9coroutine18current__coroutine(), -1, undefined);
  const resolve = (value) => {
    waiter.ret = value;
    const _bind$3 = waiter.coro;
    if (_bind$3 === undefined) {
      return;
    } else {
      const _Some = _bind$3;
      const _coro = _Some;
      _M0MP411moonbitlang5async8internal9coroutine9Coroutine4wake(_coro);
      _M0FP411moonbitlang5async8internal11event__loop10reschedule();
      return;
    }
  };
  const reject = (err) => {
    waiter.err = new _M0DTPC15error5Error51moonbitlang_2fasync_2fjs__async_2eJsError_2eJsError(err);
    const _bind$3 = waiter.coro;
    if (_bind$3 === undefined) {
      return;
    } else {
      const _Some = _bind$3;
      const _coro = _Some;
      _M0MP411moonbitlang5async8internal9coroutine9Coroutine4wake(_coro);
      _M0FP411moonbitlang5async8internal11event__loop10reschedule();
      return;
    }
  };
  _M0MP311moonbitlang5async9js__async7JsValue4then(promise, resolve, reject);
  const _defer = () => {
    waiter.coro = undefined;
  };
  if (abort_controller.$tag === 1) {
    const _Some = abort_controller;
    const _controller = _Some._0;
    let _err;
    _L: {
      const _bind$3 = _M0FP411moonbitlang5async8internal9coroutine7suspend((_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GbE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE8State__1(_cont_param, waiter, _defer));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === -1) {
            return;
          } else {
            const _Some$2 = _bind$5;
            const _payload = _Some$2;
            _cont(_payload);
            return;
          }
        }
        _err_cont(_err$2);
      }, (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GbE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE18_2adefer__try_2f91(_cont_param, _controller, _defer));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === -1) {
            return;
          } else {
            const _Some$2 = _bind$5;
            const _payload = _Some$2;
            _cont(_payload);
            return;
          }
        }
        _err_cont(_err$2);
      });
      let _bind$4;
      if (_bind$3.$tag === 1) {
        const _ok = _bind$3;
        _bind$4 = _ok._0;
      } else {
        const _err$2 = _bind$3;
        _err = _err$2._0;
        break _L;
      }
      if (_bind$4 === -1) {
        return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(-1);
      } else {
        const _Some$2 = _bind$4;
        const _payload = _Some$2;
        return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GbE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE8State__1(_payload, waiter, _defer));
      }
    }
    return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GbE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE18_2adefer__try_2f91(_err, _controller, _defer));
  } else {
    let _err;
    _L: {
      const _bind$3 = _M0FP411moonbitlang5async8internal9coroutine21protect__from__cancelGuE((_cont$2, _err_cont$2) => _M0FP411moonbitlang5async8internal9coroutine7suspend(_cont$2, _err_cont$2), (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GbE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE8State__1(_cont_param, waiter, _defer));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === -1) {
            return;
          } else {
            const _Some = _bind$5;
            const _payload = _Some;
            _cont(_payload);
            return;
          }
        }
        _err_cont(_err$2);
      }, (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GbE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE18_2adefer__try_2f90(_cont_param, _defer));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === -1) {
            return;
          } else {
            const _Some = _bind$5;
            const _payload = _Some;
            _cont(_payload);
            return;
          }
        }
        _err_cont(_err$2);
      });
      let _bind$4;
      if (_bind$3.$tag === 1) {
        const _ok = _bind$3;
        _bind$4 = _ok._0;
      } else {
        const _err$2 = _bind$3;
        _err = _err$2._0;
        break _L;
      }
      if (_bind$4 === -1) {
        return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(-1);
      } else {
        const _Some = _bind$4;
        const _payload = _Some;
        return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GbE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE8State__1(_payload, waiter, _defer));
      }
    }
    return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GbE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGbE18_2adefer__try_2f90(_err, _defer));
  }
}
function _M0MP311moonbitlang5async9js__async7Promise4waitGuE(promise, abort_controller, _cont, _err_cont) {
  const waiter = new _M0TP311moonbitlang5async9js__async13PromiseWaiterGuE(_M0FP411moonbitlang5async8internal9coroutine18current__coroutine(), -1, undefined);
  const resolve = (value) => {
    waiter.ret = value;
    const _bind$3 = waiter.coro;
    if (_bind$3 === undefined) {
      return;
    } else {
      const _Some = _bind$3;
      const _coro = _Some;
      _M0MP411moonbitlang5async8internal9coroutine9Coroutine4wake(_coro);
      _M0FP411moonbitlang5async8internal11event__loop10reschedule();
      return;
    }
  };
  const reject = (err) => {
    waiter.err = new _M0DTPC15error5Error51moonbitlang_2fasync_2fjs__async_2eJsError_2eJsError(err);
    const _bind$3 = waiter.coro;
    if (_bind$3 === undefined) {
      return;
    } else {
      const _Some = _bind$3;
      const _coro = _Some;
      _M0MP411moonbitlang5async8internal9coroutine9Coroutine4wake(_coro);
      _M0FP411moonbitlang5async8internal11event__loop10reschedule();
      return;
    }
  };
  _M0MP311moonbitlang5async9js__async7JsValue4then(promise, resolve, reject);
  const _defer = () => {
    waiter.coro = undefined;
  };
  if (abort_controller.$tag === 1) {
    const _Some = abort_controller;
    const _controller = _Some._0;
    let _err;
    _L: {
      const _bind$3 = _M0FP411moonbitlang5async8internal9coroutine7suspend((_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GuE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE8State__1(_cont_param, waiter, _defer));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === -1) {
            return;
          } else {
            const _Some$2 = _bind$5;
            const _payload = _Some$2;
            _cont(_payload);
            return;
          }
        }
        _err_cont(_err$2);
      }, (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GuE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE18_2adefer__try_2f91(_cont_param, _controller, _defer));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === -1) {
            return;
          } else {
            const _Some$2 = _bind$5;
            const _payload = _Some$2;
            _cont(_payload);
            return;
          }
        }
        _err_cont(_err$2);
      });
      let _bind$4;
      if (_bind$3.$tag === 1) {
        const _ok = _bind$3;
        _bind$4 = _ok._0;
      } else {
        const _err$2 = _bind$3;
        _err = _err$2._0;
        break _L;
      }
      if (_bind$4 === -1) {
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
      } else {
        const _Some$2 = _bind$4;
        const _payload = _Some$2;
        return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GuE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE8State__1(_payload, waiter, _defer));
      }
    }
    return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GuE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE18_2adefer__try_2f91(_err, _controller, _defer));
  } else {
    let _err;
    _L: {
      const _bind$3 = _M0FP411moonbitlang5async8internal9coroutine21protect__from__cancelGuE((_cont$2, _err_cont$2) => _M0FP411moonbitlang5async8internal9coroutine7suspend(_cont$2, _err_cont$2), (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GuE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE8State__1(_cont_param, waiter, _defer));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === -1) {
            return;
          } else {
            const _Some = _bind$5;
            const _payload = _Some;
            _cont(_payload);
            return;
          }
        }
        _err_cont(_err$2);
      }, (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GuE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE18_2adefer__try_2f90(_cont_param, _defer));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === -1) {
            return;
          } else {
            const _Some = _bind$5;
            const _payload = _Some;
            _cont(_payload);
            return;
          }
        }
        _err_cont(_err$2);
      });
      let _bind$4;
      if (_bind$3.$tag === 1) {
        const _ok = _bind$3;
        _bind$4 = _ok._0;
      } else {
        const _err$2 = _bind$3;
        _err = _err$2._0;
        break _L;
      }
      if (_bind$4 === -1) {
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
      } else {
        const _Some = _bind$4;
        const _payload = _Some;
        return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GuE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE8State__1(_payload, waiter, _defer));
      }
    }
    return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GuE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGuE18_2adefer__try_2f90(_err, _defer));
  }
}
function _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(promise, abort_controller, _cont, _err_cont) {
  const waiter = new _M0TP311moonbitlang5async9js__async13PromiseWaiterGRPB5ArrayGsEE(_M0FP411moonbitlang5async8internal9coroutine18current__coroutine(), _M0DTPC16option6OptionGRPB5ArrayGsEE4None__, undefined);
  const resolve = (value) => {
    waiter.ret = new _M0DTPC16option6OptionGRPB5ArrayGsEE4Some(value);
    const _bind$3 = waiter.coro;
    if (_bind$3 === undefined) {
      return;
    } else {
      const _Some = _bind$3;
      const _coro = _Some;
      _M0MP411moonbitlang5async8internal9coroutine9Coroutine4wake(_coro);
      _M0FP411moonbitlang5async8internal11event__loop10reschedule();
      return;
    }
  };
  const reject = (err) => {
    waiter.err = new _M0DTPC15error5Error51moonbitlang_2fasync_2fjs__async_2eJsError_2eJsError(err);
    const _bind$3 = waiter.coro;
    if (_bind$3 === undefined) {
      return;
    } else {
      const _Some = _bind$3;
      const _coro = _Some;
      _M0MP411moonbitlang5async8internal9coroutine9Coroutine4wake(_coro);
      _M0FP411moonbitlang5async8internal11event__loop10reschedule();
      return;
    }
  };
  _M0MP311moonbitlang5async9js__async7JsValue4then(promise, resolve, reject);
  const _defer = () => {
    waiter.coro = undefined;
  };
  if (abort_controller.$tag === 1) {
    const _Some = abort_controller;
    const _controller = _Some._0;
    let _err;
    _L: {
      const _bind$3 = _M0FP411moonbitlang5async8internal9coroutine7suspend((_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GRPB5ArrayGsEE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE8State__1(_cont_param, waiter, _defer));
          let _tmp$2;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _tmp$2 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          const _tmp$3 = _tmp$2;
          if (_tmp$3.$tag === 1) {
            const _Some$2 = _tmp$3;
            const _payload = _Some$2._0;
            _cont(_payload);
            return;
          } else {
            return;
          }
        }
        _err_cont(_err$2);
      }, (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GRPB5ArrayGsEE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE18_2adefer__try_2f91(_cont_param, _controller, _defer));
          let _tmp$2;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _tmp$2 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          const _tmp$3 = _tmp$2;
          if (_tmp$3.$tag === 1) {
            const _Some$2 = _tmp$3;
            const _payload = _Some$2._0;
            _cont(_payload);
            return;
          } else {
            return;
          }
        }
        _err_cont(_err$2);
      });
      let _bind$4;
      if (_bind$3.$tag === 1) {
        const _ok = _bind$3;
        _bind$4 = _ok._0;
      } else {
        const _err$2 = _bind$3;
        _err = _err$2._0;
        break _L;
      }
      if (_bind$4 === -1) {
        return new _M0DTPC16result6ResultGORPB5ArrayGsERPC15error5ErrorE2Ok(_M0DTPC16option6OptionGRPB5ArrayGsEE4None__);
      } else {
        const _Some$2 = _bind$4;
        const _payload = _Some$2;
        return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GRPB5ArrayGsEE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE8State__1(_payload, waiter, _defer));
      }
    }
    return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GRPB5ArrayGsEE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE18_2adefer__try_2f91(_err, _controller, _defer));
  } else {
    let _err;
    _L: {
      const _bind$3 = _M0FP411moonbitlang5async8internal9coroutine21protect__from__cancelGuE((_cont$2, _err_cont$2) => _M0FP411moonbitlang5async8internal9coroutine7suspend(_cont$2, _err_cont$2), (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GRPB5ArrayGsEE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE8State__1(_cont_param, waiter, _defer));
          let _tmp$2;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _tmp$2 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          const _tmp$3 = _tmp$2;
          if (_tmp$3.$tag === 1) {
            const _Some = _tmp$3;
            const _payload = _Some._0;
            _cont(_payload);
            return;
          } else {
            return;
          }
        }
        _err_cont(_err$2);
      }, (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GRPB5ArrayGsEE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE18_2adefer__try_2f90(_cont_param, _defer));
          let _tmp$2;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _tmp$2 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          const _tmp$3 = _tmp$2;
          if (_tmp$3.$tag === 1) {
            const _Some = _tmp$3;
            const _payload = _Some._0;
            _cont(_payload);
            return;
          } else {
            return;
          }
        }
        _err_cont(_err$2);
      });
      let _bind$4;
      if (_bind$3.$tag === 1) {
        const _ok = _bind$3;
        _bind$4 = _ok._0;
      } else {
        const _err$2 = _bind$3;
        _err = _err$2._0;
        break _L;
      }
      if (_bind$4 === -1) {
        return new _M0DTPC16result6ResultGORPB5ArrayGsERPC15error5ErrorE2Ok(_M0DTPC16option6OptionGRPB5ArrayGsEE4None__);
      } else {
        const _Some = _bind$4;
        const _payload = _Some;
        return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GRPB5ArrayGsEE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE8State__1(_payload, waiter, _defer));
      }
    }
    return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GRPB5ArrayGsEE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGRPB5ArrayGsEE18_2adefer__try_2f90(_err, _defer));
  }
}
function _M0MP311moonbitlang5async9js__async7Promise4waitGsE(promise, abort_controller, _cont, _err_cont) {
  const waiter = new _M0TP311moonbitlang5async9js__async13PromiseWaiterGsE(_M0FP411moonbitlang5async8internal9coroutine18current__coroutine(), undefined, undefined);
  const resolve = (value) => {
    waiter.ret = value;
    const _bind$3 = waiter.coro;
    if (_bind$3 === undefined) {
      return;
    } else {
      const _Some = _bind$3;
      const _coro = _Some;
      _M0MP411moonbitlang5async8internal9coroutine9Coroutine4wake(_coro);
      _M0FP411moonbitlang5async8internal11event__loop10reschedule();
      return;
    }
  };
  const reject = (err) => {
    waiter.err = new _M0DTPC15error5Error51moonbitlang_2fasync_2fjs__async_2eJsError_2eJsError(err);
    const _bind$3 = waiter.coro;
    if (_bind$3 === undefined) {
      return;
    } else {
      const _Some = _bind$3;
      const _coro = _Some;
      _M0MP411moonbitlang5async8internal9coroutine9Coroutine4wake(_coro);
      _M0FP411moonbitlang5async8internal11event__loop10reschedule();
      return;
    }
  };
  _M0MP311moonbitlang5async9js__async7JsValue4then(promise, resolve, reject);
  const _defer = () => {
    waiter.coro = undefined;
  };
  if (abort_controller.$tag === 1) {
    const _Some = abort_controller;
    const _controller = _Some._0;
    let _err;
    _L: {
      const _bind$3 = _M0FP411moonbitlang5async8internal9coroutine7suspend((_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GsE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE8State__1(_cont_param, waiter, _defer));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === undefined) {
            return;
          } else {
            const _Some$2 = _bind$5;
            const _payload = _Some$2;
            _cont(_payload);
            return;
          }
        }
        _err_cont(_err$2);
      }, (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GsE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE18_2adefer__try_2f91(_cont_param, _controller, _defer));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === undefined) {
            return;
          } else {
            const _Some$2 = _bind$5;
            const _payload = _Some$2;
            _cont(_payload);
            return;
          }
        }
        _err_cont(_err$2);
      });
      let _bind$4;
      if (_bind$3.$tag === 1) {
        const _ok = _bind$3;
        _bind$4 = _ok._0;
      } else {
        const _err$2 = _bind$3;
        _err = _err$2._0;
        break _L;
      }
      if (_bind$4 === -1) {
        return new _M0DTPC16result6ResultGOsRPC15error5ErrorE2Ok(undefined);
      } else {
        const _Some$2 = _bind$4;
        const _payload = _Some$2;
        return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GsE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE8State__1(_payload, waiter, _defer));
      }
    }
    return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GsE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE18_2adefer__try_2f91(_err, _controller, _defer));
  } else {
    let _err;
    _L: {
      const _bind$3 = _M0FP411moonbitlang5async8internal9coroutine21protect__from__cancelGuE((_cont$2, _err_cont$2) => _M0FP411moonbitlang5async8internal9coroutine7suspend(_cont$2, _err_cont$2), (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GsE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE8State__1(_cont_param, waiter, _defer));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === undefined) {
            return;
          } else {
            const _Some = _bind$5;
            const _payload = _Some;
            _cont(_payload);
            return;
          }
        }
        _err_cont(_err$2);
      }, (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GsE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE18_2adefer__try_2f90(_cont_param, _defer));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === undefined) {
            return;
          } else {
            const _Some = _bind$5;
            const _payload = _Some;
            _cont(_payload);
            return;
          }
        }
        _err_cont(_err$2);
      });
      let _bind$4;
      if (_bind$3.$tag === 1) {
        const _ok = _bind$3;
        _bind$4 = _ok._0;
      } else {
        const _err$2 = _bind$3;
        _err = _err$2._0;
        break _L;
      }
      if (_bind$4 === -1) {
        return new _M0DTPC16result6ResultGOsRPC15error5ErrorE2Ok(undefined);
      } else {
        const _Some = _bind$4;
        const _payload = _Some;
        return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GsE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE8State__1(_payload, waiter, _defer));
      }
    }
    return _M0MP311moonbitlang5async9js__async7Promise4waitN16_2aasync__driverS165GsE(new _M0DTP311moonbitlang5async9js__async54_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3awaitL5StateGsE18_2adefer__try_2f90(_err, _defer));
  }
}
function _M0MP311moonbitlang5async9js__async7Promise11from__asyncN16_2aasync__driverS283GuE(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _$42$defer_try$47$133 = _state$2;
        const _defer = _$42$defer_try$47$133._1;
        const _err = _$42$defer_try$47$133._0;
        _defer();
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE3Err(_err);
      }
      case 1: {
        const _State_1 = _state$2;
        const _defer$2 = _State_1._1;
        const _cont_param = _State_1._0;
        _defer$2();
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(_cont_param);
      }
      case 2: {
        const _$42$try$47$138 = _state$2;
        const _defer$3 = _$42$try$47$138._2;
        const reject = _$42$try$47$138._1;
        const _try_err = _$42$try$47$138._0;
        if (_try_err.$tag === 1) {
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE19_2adefer__try_2f133(_try_err, _defer$3);
          continue _L;
        } else {
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE8State__1(reject(_M0FP15Error10to__string(_try_err)), _defer$3);
          continue _L;
        }
      }
      default: {
        const _State_3 = _state$2;
        const _defer$4 = _State_3._3;
        const reject$2 = _State_3._2;
        const resolve = _State_3._1;
        const _cont_param$2 = _State_3._0;
        if (_cont_param$2 === -1) {
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE8State__1(reject$2(_M0MP311moonbitlang5async9js__async7JsValue12abort__error()), _defer$4);
          continue _L;
        } else {
          const _Some = _cont_param$2;
          const _ret = _Some;
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE8State__1(resolve(_ret), _defer$4);
          continue _L;
        }
      }
    }
  }
}
function _M0MP311moonbitlang5async9js__async7Promise11from__asyncN16_2aasync__driverS283GRP46f4ah6o3dsh7browser2sw10SwResponseE(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _$42$defer_try$47$133 = _state$2;
        const _defer = _$42$defer_try$47$133._1;
        const _err = _$42$defer_try$47$133._0;
        _defer();
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE3Err(_err);
      }
      case 1: {
        const _State_1 = _state$2;
        const _defer$2 = _State_1._1;
        const _cont_param = _State_1._0;
        _defer$2();
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(_cont_param);
      }
      case 2: {
        const _$42$try$47$138 = _state$2;
        const _defer$3 = _$42$try$47$138._2;
        const reject = _$42$try$47$138._1;
        const _try_err = _$42$try$47$138._0;
        if (_try_err.$tag === 1) {
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE19_2adefer__try_2f133(_try_err, _defer$3);
          continue _L;
        } else {
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE8State__1(reject(_M0FP15Error10to__string(_try_err)), _defer$3);
          continue _L;
        }
      }
      default: {
        const _State_3 = _state$2;
        const _defer$4 = _State_3._3;
        const reject$2 = _State_3._2;
        const resolve = _State_3._1;
        const _cont_param$2 = _State_3._0;
        if (_cont_param$2.$tag === 0) {
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE8State__1(reject$2(_M0MP311moonbitlang5async9js__async7JsValue12abort__error()), _defer$4);
          continue _L;
        } else {
          const _Some = _cont_param$2;
          const _ret = _Some._0;
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE8State__1(resolve(_ret), _defer$4);
          continue _L;
        }
      }
    }
  }
}
function _M0MP311moonbitlang5async9js__async7Promise11from__asyncN16_2aasync__driverS283GbE(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _$42$defer_try$47$133 = _state$2;
        const _defer = _$42$defer_try$47$133._1;
        const _err = _$42$defer_try$47$133._0;
        _defer();
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE3Err(_err);
      }
      case 1: {
        const _State_1 = _state$2;
        const _defer$2 = _State_1._1;
        const _cont_param = _State_1._0;
        _defer$2();
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(_cont_param);
      }
      case 2: {
        const _$42$try$47$138 = _state$2;
        const _defer$3 = _$42$try$47$138._2;
        const reject = _$42$try$47$138._1;
        const _try_err = _$42$try$47$138._0;
        if (_try_err.$tag === 1) {
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE19_2adefer__try_2f133(_try_err, _defer$3);
          continue _L;
        } else {
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE8State__1(reject(_M0FP15Error10to__string(_try_err)), _defer$3);
          continue _L;
        }
      }
      default: {
        const _State_3 = _state$2;
        const _defer$4 = _State_3._3;
        const reject$2 = _State_3._2;
        const resolve = _State_3._1;
        const _cont_param$2 = _State_3._0;
        if (_cont_param$2 === -1) {
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE8State__1(reject$2(_M0MP311moonbitlang5async9js__async7JsValue12abort__error()), _defer$4);
          continue _L;
        } else {
          const _Some = _cont_param$2;
          const _ret = _Some;
          _tmp$2 = new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE8State__1(resolve(_ret), _defer$4);
          continue _L;
        }
      }
    }
  }
}
function _M0MP311moonbitlang5async9js__async7Promise11from__asyncGuE(f, abort_signal) {
  const promise = _M0MP311moonbitlang5async9js__async7JsValue12new__promise((resolve, reject) => {
    _M0FP411moonbitlang5async8internal9coroutine5spawn((_cont, _err_cont) => {
      const coro = _M0FP411moonbitlang5async8internal9coroutine18current__coroutine();
      const abort_handler = () => {
        _M0MP411moonbitlang5async8internal9coroutine9Coroutine6cancel(coro);
      };
      if (abort_signal.$tag === 1) {
        const _Some = abort_signal;
        const _signal = _Some._0;
        _M0MP311moonbitlang5async9js__async11AbortSignal9on__abort(_signal, abort_handler);
      }
      const _defer = () => {
        if (abort_signal.$tag === 1) {
          const _Some = abort_signal;
          const _signal = _Some._0;
          _M0MP311moonbitlang5async9js__async11AbortSignal23remove__abort__listener(_signal, abort_handler);
          return;
        } else {
          return;
        }
      };
      if (abort_signal.$tag === 1) {
        const _Some = abort_signal;
        const _signal = _Some._0;
        if (_M0MP311moonbitlang5async9js__async11AbortSignal7aborted(_signal)) {
          _M0MP411moonbitlang5async8internal9coroutine9Coroutine6cancel(coro);
        }
      }
      let _err;
      _L: {
        const _bind$3 = _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationGuE(f, (_cont_param) => {
          let _err$2;
          _L$2: {
            const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise11from__asyncN16_2aasync__driverS283GuE(new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE8State__3(_cont_param, resolve, reject, _defer));
            let _bind$5;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _bind$5 = _ok._0;
            } else {
              const _err$3 = _bind$4;
              _err$2 = _err$3._0;
              break _L$2;
            }
            if (_bind$5 === -1) {
              return;
            } else {
              const _Some = _bind$5;
              const _payload = _Some;
              _cont(_payload);
              return;
            }
          }
          _err_cont(_err$2);
        }, (_cont_param) => {
          let _err$2;
          _L$2: {
            const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise11from__asyncN16_2aasync__driverS283GuE(new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE12_2atry_2f138(_cont_param, reject, _defer));
            let _bind$5;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _bind$5 = _ok._0;
            } else {
              const _err$3 = _bind$4;
              _err$2 = _err$3._0;
              break _L$2;
            }
            if (_bind$5 === -1) {
              return;
            } else {
              const _Some = _bind$5;
              const _payload = _Some;
              _cont(_payload);
              return;
            }
          }
          _err_cont(_err$2);
        });
        let _tmp$2;
        if (_bind$3.$tag === 1) {
          const _ok = _bind$3;
          _tmp$2 = _ok._0;
        } else {
          const _err$2 = _bind$3;
          _err = _err$2._0;
          break _L;
        }
        const _tmp$3 = _tmp$2;
        if (_tmp$3.$tag === 1) {
          const _Some = _tmp$3;
          const _payload = _Some._0;
          return _M0MP311moonbitlang5async9js__async7Promise11from__asyncN16_2aasync__driverS283GuE(new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE8State__3(_payload, resolve, reject, _defer));
        } else {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        }
      }
      return _M0MP311moonbitlang5async9js__async7Promise11from__asyncN16_2aasync__driverS283GuE(new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGuE12_2atry_2f138(_err, reject, _defer));
    }, "src/js_async/js_async.mbt:215:13-239:7@moonbitlang/async");
  });
  _M0FP411moonbitlang5async8internal11event__loop10reschedule();
  return promise;
}
function _M0MP311moonbitlang5async9js__async7Promise11from__asyncGRP46f4ah6o3dsh7browser2sw10SwResponseE(f, abort_signal) {
  const promise = _M0MP311moonbitlang5async9js__async7JsValue12new__promise((resolve, reject) => {
    _M0FP411moonbitlang5async8internal9coroutine5spawn((_cont, _err_cont) => {
      const coro = _M0FP411moonbitlang5async8internal9coroutine18current__coroutine();
      const abort_handler = () => {
        _M0MP411moonbitlang5async8internal9coroutine9Coroutine6cancel(coro);
      };
      if (abort_signal.$tag === 1) {
        const _Some = abort_signal;
        const _signal = _Some._0;
        _M0MP311moonbitlang5async9js__async11AbortSignal9on__abort(_signal, abort_handler);
      }
      const _defer = () => {
        if (abort_signal.$tag === 1) {
          const _Some = abort_signal;
          const _signal = _Some._0;
          _M0MP311moonbitlang5async9js__async11AbortSignal23remove__abort__listener(_signal, abort_handler);
          return;
        } else {
          return;
        }
      };
      if (abort_signal.$tag === 1) {
        const _Some = abort_signal;
        const _signal = _Some._0;
        if (_M0MP311moonbitlang5async9js__async11AbortSignal7aborted(_signal)) {
          _M0MP411moonbitlang5async8internal9coroutine9Coroutine6cancel(coro);
        }
      }
      let _err;
      _L: {
        const _bind$3 = _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationGRP46f4ah6o3dsh7browser2sw10SwResponseE(f, (_cont_param) => {
          let _err$2;
          _L$2: {
            const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise11from__asyncN16_2aasync__driverS283GRP46f4ah6o3dsh7browser2sw10SwResponseE(new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE8State__3(_cont_param, resolve, reject, _defer));
            let _bind$5;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _bind$5 = _ok._0;
            } else {
              const _err$3 = _bind$4;
              _err$2 = _err$3._0;
              break _L$2;
            }
            if (_bind$5 === -1) {
              return;
            } else {
              const _Some = _bind$5;
              const _payload = _Some;
              _cont(_payload);
              return;
            }
          }
          _err_cont(_err$2);
        }, (_cont_param) => {
          let _err$2;
          _L$2: {
            const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise11from__asyncN16_2aasync__driverS283GRP46f4ah6o3dsh7browser2sw10SwResponseE(new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE12_2atry_2f138(_cont_param, reject, _defer));
            let _bind$5;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _bind$5 = _ok._0;
            } else {
              const _err$3 = _bind$4;
              _err$2 = _err$3._0;
              break _L$2;
            }
            if (_bind$5 === -1) {
              return;
            } else {
              const _Some = _bind$5;
              const _payload = _Some;
              _cont(_payload);
              return;
            }
          }
          _err_cont(_err$2);
        });
        let _bind$4;
        if (_bind$3.$tag === 1) {
          const _ok = _bind$3;
          _bind$4 = _ok._0;
        } else {
          const _err$2 = _bind$3;
          _err = _err$2._0;
          break _L;
        }
        if (_bind$4 === undefined) {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        } else {
          const _Some = _bind$4;
          const _payload = _Some;
          return _M0MP311moonbitlang5async9js__async7Promise11from__asyncN16_2aasync__driverS283GRP46f4ah6o3dsh7browser2sw10SwResponseE(new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE8State__3(_payload, resolve, reject, _defer));
        }
      }
      return _M0MP311moonbitlang5async9js__async7Promise11from__asyncN16_2aasync__driverS283GRP46f4ah6o3dsh7browser2sw10SwResponseE(new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGRP46f4ah6o3dsh7browser2sw10SwResponseE12_2atry_2f138(_err, reject, _defer));
    }, "src/js_async/js_async.mbt:215:13-239:7@moonbitlang/async");
  });
  _M0FP411moonbitlang5async8internal11event__loop10reschedule();
  return promise;
}
function _M0MP311moonbitlang5async9js__async7Promise11from__asyncGbE(f, abort_signal) {
  const promise = _M0MP311moonbitlang5async9js__async7JsValue12new__promise((resolve, reject) => {
    _M0FP411moonbitlang5async8internal9coroutine5spawn((_cont, _err_cont) => {
      const coro = _M0FP411moonbitlang5async8internal9coroutine18current__coroutine();
      const abort_handler = () => {
        _M0MP411moonbitlang5async8internal9coroutine9Coroutine6cancel(coro);
      };
      if (abort_signal.$tag === 1) {
        const _Some = abort_signal;
        const _signal = _Some._0;
        _M0MP311moonbitlang5async9js__async11AbortSignal9on__abort(_signal, abort_handler);
      }
      const _defer = () => {
        if (abort_signal.$tag === 1) {
          const _Some = abort_signal;
          const _signal = _Some._0;
          _M0MP311moonbitlang5async9js__async11AbortSignal23remove__abort__listener(_signal, abort_handler);
          return;
        } else {
          return;
        }
      };
      if (abort_signal.$tag === 1) {
        const _Some = abort_signal;
        const _signal = _Some._0;
        if (_M0MP311moonbitlang5async9js__async11AbortSignal7aborted(_signal)) {
          _M0MP411moonbitlang5async8internal9coroutine9Coroutine6cancel(coro);
        }
      }
      let _err;
      _L: {
        const _bind$3 = _M0FP411moonbitlang5async8internal9coroutine20handle__cancellationGbE(f, (_cont_param) => {
          let _err$2;
          _L$2: {
            const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise11from__asyncN16_2aasync__driverS283GbE(new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE8State__3(_cont_param, resolve, reject, _defer));
            let _bind$5;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _bind$5 = _ok._0;
            } else {
              const _err$3 = _bind$4;
              _err$2 = _err$3._0;
              break _L$2;
            }
            if (_bind$5 === -1) {
              return;
            } else {
              const _Some = _bind$5;
              const _payload = _Some;
              _cont(_payload);
              return;
            }
          }
          _err_cont(_err$2);
        }, (_cont_param) => {
          let _err$2;
          _L$2: {
            const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise11from__asyncN16_2aasync__driverS283GbE(new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE12_2atry_2f138(_cont_param, reject, _defer));
            let _bind$5;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _bind$5 = _ok._0;
            } else {
              const _err$3 = _bind$4;
              _err$2 = _err$3._0;
              break _L$2;
            }
            if (_bind$5 === -1) {
              return;
            } else {
              const _Some = _bind$5;
              const _payload = _Some;
              _cont(_payload);
              return;
            }
          }
          _err_cont(_err$2);
        });
        let _tmp$2;
        if (_bind$3.$tag === 1) {
          const _ok = _bind$3;
          _tmp$2 = _ok._0;
        } else {
          const _err$2 = _bind$3;
          _err = _err$2._0;
          break _L;
        }
        const _tmp$3 = _tmp$2;
        if (_tmp$3.$tag === 1) {
          const _Some = _tmp$3;
          const _payload = _Some._0;
          return _M0MP311moonbitlang5async9js__async7Promise11from__asyncN16_2aasync__driverS283GbE(new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE8State__3(_payload, resolve, reject, _defer));
        } else {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        }
      }
      return _M0MP311moonbitlang5async9js__async7Promise11from__asyncN16_2aasync__driverS283GbE(new _M0DTP311moonbitlang5async9js__async85_40moonbitlang_2fasync_2fjs__async_2ePromise_3a_3afrom__async_2elambda_2elambda_2f280L5StateGbE12_2atry_2f138(_err, reject, _defer));
    }, "src/js_async/js_async.mbt:215:13-239:7@moonbitlang/async");
  });
  _M0FP411moonbitlang5async8internal11event__loop10reschedule();
  return promise;
}
function _M0IP311moonbitlang5async9js__async7JsErrorPB4Show6output(self, logger) {
  const _JsError = self;
  const _value = _JsError._0;
  logger.method_table.method_4(logger.self, { self: _M0MP311moonbitlang5async9js__async7JsValue10to__string(_value), method_table: _M0FP052String_24as_24_40moonbitlang_2fcore_2fbuiltin_2eShow });
}
function _M0FP46f4ah6o3dsh7browser2sw21sw__generation__nonce() {
  return `${_M0FP46f4ah6o3dsh7browser2sw11sw__now__ms()}-${_M0FP46f4ah6o3dsh7browser2sw18sw__random__suffix()}`;
}
function _M0FP46f4ah6o3dsh7browser2sw22encoded__metadata__key(origin, prefix, value) {
  return `${origin}${prefix}${_M0FP46f4ah6o3dsh7browser2sw21sw__encode__component(value)}`;
}
function _M0FP46f4ah6o3dsh7browser2sw20is__generation__name(name) {
  return _M0MPC16string6String11has__prefix(name, new _M0TPC16string10StringView(_M0FP46f4ah6o3dsh7browser2sw18generation__prefix, 0, _M0FP46f4ah6o3dsh7browser2sw18generation__prefix.length)) || _M0MPC15array13ReadOnlyArray8containsGsE(_M0FP46f4ah6o3dsh7browser2sw20legacy__cache__names, name);
}
function _M0FP46f4ah6o3dsh7browser2sw26parse__nonnegative__length(value) {
  if (value === "") {
    return undefined;
  }
  let result = 0;
  const _bind$3 = value.length;
  let _tmp$2 = 0;
  while (true) {
    const _string_index = _tmp$2;
    if (_string_index < _bind$3) {
      let _decoded_next_string_index;
      let _decoded_char;
      _L: {
        const _bind$4 = value.charCodeAt(_string_index);
        if (_bind$4 >= 55296 && _bind$4 <= 56319 && (_string_index + 1 | 0) < _bind$3) {
          const _bind$5 = value.charCodeAt(_string_index + 1 | 0);
          if (_bind$5 >= 56320 && _bind$5 <= 57343) {
            const _tmp$3 = _string_index + 2 | 0;
            const _p = (((Math.imul(_bind$4 - 55296 | 0, 1024) | 0) + _bind$5 | 0) - 56320 | 0) + 65536 | 0;
            _decoded_next_string_index = _tmp$3;
            _decoded_char = _p;
            break _L;
          } else {
            const _tmp$3 = _string_index + 1 | 0;
            const _p = _bind$4;
            _decoded_next_string_index = _tmp$3;
            _decoded_char = _p;
            break _L;
          }
        } else {
          const _tmp$3 = _string_index + 1 | 0;
          const _p = _bind$4;
          _decoded_next_string_index = _tmp$3;
          _decoded_char = _p;
          break _L;
        }
      }
      if (_decoded_char < 48 || _decoded_char > 57) {
        return undefined;
      }
      result = ((Math.imul(result, 10) | 0) + _decoded_char | 0) - 48 | 0;
      if (result > 8388608) {
        return result;
      }
      _tmp$2 = _decoded_next_string_index;
      continue;
    } else {
      break;
    }
  }
  return result;
}
function _M0FP46f4ah6o3dsh7browser2sw30has__private__cache__directive(value) {
  const _it = _M0MPC16string6String5split(_M0MPC16string6String9to__lower(value), new _M0TPC16string10StringView(_M0FP46f4ah6o3dsh7browser2sw30has__private__cache__directiveN7_2abindS232, 0, _M0FP46f4ah6o3dsh7browser2sw30has__private__cache__directiveN7_2abindS232.length));
  while (true) {
    const _bind$3 = _M0MPB4Iter4nextGRP411moonbitlang5async8internal9coroutine9CoroutineE(_it);
    if (_bind$3 === undefined) {
      break;
    } else {
      const _Some = _bind$3;
      const _directive = _Some;
      const name = _M0MPC16string10StringView9to__owned(_M0MPC16string10StringView4trim(_M0MPC15array5Array2atGRPC16string10StringViewE(_M0MPB4Iter9to__arrayGRPC16string10StringViewE(_M0MPC16string10StringView5split(_directive, new _M0TPC16string10StringView(_M0FP46f4ah6o3dsh7browser2sw30has__private__cache__directiveN7_2abindS221, 0, _M0FP46f4ah6o3dsh7browser2sw30has__private__cache__directiveN7_2abindS221.length))), 0), undefined));
      if (name === "private") {
        return true;
      }
      continue;
    }
  }
  return false;
}
function _M0FP46f4ah6o3dsh7browser2sw27cancel__shell__body__readerN16_2aasync__driverS440(_state) {
  let _tmp$2 = _state;
  while (true) {
    const _state$2 = _tmp$2;
    if (_state$2.$tag === 0) {
      return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(undefined);
    } else {
      const _$42$try$47$233 = _state$2;
      const _try_err = _$42$try$47$233._0;
      if (_try_err.$tag === 1) {
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE3Err(_try_err);
      } else {
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw60_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecancel__shell__body__readerL5State8State__0(undefined);
        continue;
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw27cancel__shell__body__reader(reader, _cont, _err_cont) {
  let _err;
  _L: {
    const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGuE(_M0FP46f4ah6o3dsh7browser2sw18sw__reader__cancel(reader), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param) => {
      let _err$2;
      _L$2: {
        const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw27cancel__shell__body__readerN16_2aasync__driverS440(new _M0DTP46f4ah6o3dsh7browser2sw60_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecancel__shell__body__readerL5State8State__0(_cont_param));
        let _bind$5;
        if (_bind$4.$tag === 1) {
          const _ok = _bind$4;
          _bind$5 = _ok._0;
        } else {
          const _err$3 = _bind$4;
          _err$2 = _err$3._0;
          break _L$2;
        }
        if (_bind$5 === -1) {
          return;
        } else {
          const _Some = _bind$5;
          const _payload = _Some;
          _cont(_payload);
          return;
        }
      }
      _err_cont(_err$2);
    }, (_cont_param) => {
      let _err$2;
      _L$2: {
        const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw27cancel__shell__body__readerN16_2aasync__driverS440(new _M0DTP46f4ah6o3dsh7browser2sw60_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecancel__shell__body__readerL5State12_2atry_2f233(_cont_param));
        let _bind$5;
        if (_bind$4.$tag === 1) {
          const _ok = _bind$4;
          _bind$5 = _ok._0;
        } else {
          const _err$3 = _bind$4;
          _err$2 = _err$3._0;
          break _L$2;
        }
        if (_bind$5 === -1) {
          return;
        } else {
          const _Some = _bind$5;
          const _payload = _Some;
          _cont(_payload);
          return;
        }
      }
      _err_cont(_err$2);
    });
    let _bind$4;
    if (_bind$3.$tag === 1) {
      const _ok = _bind$3;
      _bind$4 = _ok._0;
    } else {
      const _err$2 = _bind$3;
      _err = _err$2._0;
      break _L;
    }
    if (_bind$4 === -1) {
      return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
    } else {
      const _Some = _bind$4;
      const _payload = _Some;
      return _M0FP46f4ah6o3dsh7browser2sw27cancel__shell__body__readerN16_2aasync__driverS440(new _M0DTP46f4ah6o3dsh7browser2sw60_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecancel__shell__body__readerL5State8State__0(_payload));
    }
  }
  return _M0FP46f4ah6o3dsh7browser2sw27cancel__shell__body__readerN16_2aasync__driverS440(new _M0DTP46f4ah6o3dsh7browser2sw60_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecancel__shell__body__readerL5State12_2atry_2f233(_err));
}
function _M0FP46f4ah6o3dsh7browser2sw30is__cacheable__shell__response(request, response, expected_url) {
  if (!_M0FP46f4ah6o3dsh7browser2sw16sw__response__ok(response) || _M0FP46f4ah6o3dsh7browser2sw18sw__response__type(response) === "opaque") {
    return false;
  }
  if (_M0FP46f4ah6o3dsh7browser2sw24sw__request__has__header(request, "authorization")) {
    return false;
  }
  const mime = _M0MPC16string6String9to__lower(_M0MPC16string10StringView9to__owned(_M0MPC16string10StringView4trim(_M0MPC15array5Array2atGRPC16string10StringViewE(_M0MPB4Iter9to__arrayGRPC16string10StringViewE(_M0MPC16string6String5split(_M0FP46f4ah6o3dsh7browser2sw20sw__response__header(response, "content-type"), new _M0TPC16string10StringView(_M0FP46f4ah6o3dsh7browser2sw30is__cacheable__shell__responseN7_2abindS239, 0, _M0FP46f4ah6o3dsh7browser2sw30is__cacheable__shell__responseN7_2abindS239.length))), 0), undefined)));
  if (!_M0MPC15array13ReadOnlyArray8containsGsE(_M0FP46f4ah6o3dsh7browser2sw21shell__content__types, mime)) {
    return false;
  }
  const cache_control = _M0FP46f4ah6o3dsh7browser2sw20sw__response__header(response, "cache-control");
  let _tmp$2;
  if (_M0FP46f4ah6o3dsh7browser2sw30has__private__cache__directive(cache_control)) {
    _tmp$2 = true;
  } else {
    let _tmp$3;
    const _p = _M0FP46f4ah6o3dsh7browser2sw20sw__response__header(response, "set-cookie");
    const _p$2 = "";
    if (!(_p === _p$2)) {
      _tmp$3 = true;
    } else {
      _tmp$3 = _M0IP016_24default__implPB2Eq10not__equalGRPC16string10StringViewE(_M0MPC16string6String4trim(_M0FP46f4ah6o3dsh7browser2sw20sw__response__header(response, "vary"), undefined), new _M0TPC16string10StringView(_M0FP46f4ah6o3dsh7browser2sw30is__cacheable__shell__responseN7_2abindS238, 0, _M0FP46f4ah6o3dsh7browser2sw30is__cacheable__shell__responseN7_2abindS238.length));
    }
    _tmp$2 = _tmp$3;
  }
  if (_tmp$2) {
    return false;
  }
  const response_url = _M0FP46f4ah6o3dsh7browser2sw17sw__response__url(response);
  return response_url === "" || response_url === expected_url;
}
function _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN16_2aasync__driverS461(_env, _state) {
  const constr = _env._4;
  const constr$2 = _env._3;
  const constr$3 = _env._2;
  const _err_cont = _env._1;
  const constr$4 = _env._0;
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _$42$defer_try$47$246 = _state$2;
        const _defer = _$42$defer_try$47$246._1;
        const _err = _$42$defer_try$47$246._0;
        _defer();
        return new _M0DTPC16result6ResultGObRPC15error5ErrorE3Err(_err);
      }
      case 1: {
        const _State_1 = _state$2;
        const _defer$2 = _State_1._1;
        _defer$2();
        return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(constr);
      }
      case 2: {
        const _$42$while_2 = _state$2;
        const _cont = _$42$while_2._4;
        const _defer$3 = _$42$while_2._3;
        const asset_bytes = _$42$while_2._2;
        const reader = _$42$while_2._1;
        const bundle_bytes = _$42$while_2._0;
        let _err$2;
        _L$2: {
          const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(_M0FP46f4ah6o3dsh7browser2sw16sw__reader__read(reader), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param) => {
            let _err$3;
            _L$3: {
              const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN16_2aasync__driverS461(_env, new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__5(_cont_param, bundle_bytes, reader, asset_bytes, _defer$3, _cont, _err_cont));
              let _bind$5;
              if (_bind$4.$tag === 1) {
                const _ok = _bind$4;
                _bind$5 = _ok._0;
              } else {
                const _err$4 = _bind$4;
                _err$3 = _err$4._0;
                break _L$3;
              }
              if (_bind$5 === -1) {
                return;
              } else {
                const _Some = _bind$5;
                const _payload = _Some;
                _cont(_payload);
                return;
              }
            }
            _err_cont(_err$3);
          }, (_cont_param) => {
            let _err$3;
            _L$3: {
              const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN16_2aasync__driverS461(_env, new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State12_2atry_2f250(_cont_param, reader, _defer$3, _cont, _err_cont));
              let _bind$5;
              if (_bind$4.$tag === 1) {
                const _ok = _bind$4;
                _bind$5 = _ok._0;
              } else {
                const _err$4 = _bind$4;
                _err$3 = _err$4._0;
                break _L$3;
              }
              if (_bind$5 === -1) {
                return;
              } else {
                const _Some = _bind$5;
                const _payload = _Some;
                _cont(_payload);
                return;
              }
            }
            _err_cont(_err$3);
          });
          let _tmp$3;
          if (_bind$3.$tag === 1) {
            const _ok = _bind$3;
            _tmp$3 = _ok._0;
          } else {
            const _err$3 = _bind$3;
            _err$2 = _err$3._0;
            break _L$2;
          }
          const _tmp$4 = _tmp$3;
          if (_tmp$4.$tag === 1) {
            const _Some = _tmp$4;
            const _payload = _Some._0;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__5(_payload, bundle_bytes, reader, asset_bytes, _defer$3, _cont, _err_cont);
            continue _L;
          } else {
            return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(-1);
          }
        }
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State12_2atry_2f250(_err$2, reader, _defer$3, _cont, _err_cont);
        continue _L;
      }
      case 3: {
        const _State_3 = _state$2;
        const _cont$2 = _State_3._5;
        const _defer$4 = _State_3._4;
        const asset_bytes$2 = _State_3._3;
        const reader$2 = _State_3._2;
        const bundle_bytes$2 = _State_3._1;
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State11_2awhile__2(bundle_bytes$2, reader$2, asset_bytes$2, _defer$4, _cont$2);
        continue _L;
      }
      case 4: {
        const _State_4 = _state$2;
        const _defer$5 = _State_4._1;
        _defer$5();
        return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(constr$3);
      }
      case 5: {
        const _State_5 = _state$2;
        const _err_cont$2 = _State_5._6;
        const _cont$3 = _State_5._5;
        const _defer$6 = _State_5._4;
        const asset_bytes$3 = _State_5._3;
        const reader$3 = _State_5._2;
        const bundle_bytes$3 = _State_5._1;
        const _cont_param = _State_5._0;
        if (_M0FP46f4ah6o3dsh7browser2sw19sw__chunk__is__done(_cont_param)) {
          _defer$6();
          return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(constr$2);
        }
        const chunk_bytes = _M0FP46f4ah6o3dsh7browser2sw23sw__chunk__byte__length(_cont_param);
        asset_bytes$3.val = asset_bytes$3.val + chunk_bytes | 0;
        bundle_bytes$3.val = bundle_bytes$3.val + chunk_bytes | 0;
        if (asset_bytes$3.val > 4194304 || bundle_bytes$3.val > 8388608) {
          let _err$3;
          _L$3: {
            const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw27cancel__shell__body__reader(reader$3, (_cont_param$2) => {
              let _err$4;
              _L$4: {
                const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN16_2aasync__driverS461(_env, new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__4(_cont_param$2, _defer$6));
                let _bind$5;
                if (_bind$4.$tag === 1) {
                  const _ok = _bind$4;
                  _bind$5 = _ok._0;
                } else {
                  const _err$5 = _bind$4;
                  _err$4 = _err$5._0;
                  break _L$4;
                }
                if (_bind$5 === -1) {
                  return;
                } else {
                  const _Some = _bind$5;
                  const _payload = _Some;
                  _cont$3(_payload);
                  return;
                }
              }
              _err_cont$2(_err$4);
            }, (_cont_param$2) => {
              let _err$4;
              _L$4: {
                const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN16_2aasync__driverS461(_env, new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State19_2adefer__try_2f246(_cont_param$2, _defer$6));
                let _bind$5;
                if (_bind$4.$tag === 1) {
                  const _ok = _bind$4;
                  _bind$5 = _ok._0;
                } else {
                  const _err$5 = _bind$4;
                  _err$4 = _err$5._0;
                  break _L$4;
                }
                if (_bind$5 === -1) {
                  return;
                } else {
                  const _Some = _bind$5;
                  const _payload = _Some;
                  _cont$3(_payload);
                  return;
                }
              }
              _err_cont$2(_err$4);
            });
            let _bind$4;
            if (_bind$3.$tag === 1) {
              const _ok = _bind$3;
              _bind$4 = _ok._0;
            } else {
              const _err$4 = _bind$3;
              _err$3 = _err$4._0;
              break _L$3;
            }
            if (_bind$4 === -1) {
              return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(-1);
            } else {
              const _Some = _bind$4;
              const _payload = _Some;
              _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__4(_payload, _defer$6);
              continue _L;
            }
          }
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State19_2adefer__try_2f246(_err$3, _defer$6);
          continue _L;
        } else {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__3(undefined, bundle_bytes$3, reader$3, asset_bytes$3, _defer$6, _cont$3);
          continue _L;
        }
      }
      case 6: {
        const _State_6 = _state$2;
        const _defer$7 = _State_6._1;
        _defer$7();
        return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(constr$4);
      }
      default: {
        const _$42$try$47$250 = _state$2;
        const _err_cont$3 = _$42$try$47$250._4;
        const _cont$4 = _$42$try$47$250._3;
        const _defer$8 = _$42$try$47$250._2;
        const reader$4 = _$42$try$47$250._1;
        const _try_err = _$42$try$47$250._0;
        if (_try_err.$tag === 1) {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State19_2adefer__try_2f246(_try_err, _defer$8);
          continue _L;
        } else {
          let _err$3;
          _L$3: {
            const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw27cancel__shell__body__reader(reader$4, (_cont_param$2) => {
              let _err$4;
              _L$4: {
                const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN16_2aasync__driverS461(_env, new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__6(_cont_param$2, _defer$8));
                let _bind$5;
                if (_bind$4.$tag === 1) {
                  const _ok = _bind$4;
                  _bind$5 = _ok._0;
                } else {
                  const _err$5 = _bind$4;
                  _err$4 = _err$5._0;
                  break _L$4;
                }
                if (_bind$5 === -1) {
                  return;
                } else {
                  const _Some = _bind$5;
                  const _payload = _Some;
                  _cont$4(_payload);
                  return;
                }
              }
              _err_cont$3(_err$4);
            }, (_cont_param$2) => {
              let _err$4;
              _L$4: {
                const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN16_2aasync__driverS461(_env, new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State19_2adefer__try_2f246(_cont_param$2, _defer$8));
                let _bind$5;
                if (_bind$4.$tag === 1) {
                  const _ok = _bind$4;
                  _bind$5 = _ok._0;
                } else {
                  const _err$5 = _bind$4;
                  _err$4 = _err$5._0;
                  break _L$4;
                }
                if (_bind$5 === -1) {
                  return;
                } else {
                  const _Some = _bind$5;
                  const _payload = _Some;
                  _cont$4(_payload);
                  return;
                }
              }
              _err_cont$3(_err$4);
            });
            let _bind$4;
            if (_bind$3.$tag === 1) {
              const _ok = _bind$3;
              _bind$4 = _ok._0;
            } else {
              const _err$4 = _bind$3;
              _err$3 = _err$4._0;
              break _L$3;
            }
            if (_bind$4 === -1) {
              return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(-1);
            } else {
              const _Some = _bind$4;
              const _payload = _Some;
              _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State8State__6(_payload, _defer$8);
              continue _L;
            }
          }
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State19_2adefer__try_2f246(_err$3, _defer$8);
          continue _L;
        }
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__body(response, bundle_bytes, _cont, _err_cont) {
  const _env = { _0: _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN6constrS1705, _1: _err_cont, _2: _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN6constrS1703, _3: _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN6constrS1704, _4: _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN6constrS1702 };
  const declared = _M0FP46f4ah6o3dsh7browser2sw20sw__response__header(response, "content-length");
  const _p = "";
  if (!(declared === _p)) {
    const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw26parse__nonnegative__length(declared);
    if (_bind$3 === undefined) {
      return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(_M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN6constrS1706);
    } else {
      const _Some = _bind$3;
      const _length = _Some;
      if (_length > 4194304 || _length > (8388608 - bundle_bytes.val | 0)) {
        return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(_M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN6constrS1707);
      }
    }
  }
  if (!_M0FP46f4ah6o3dsh7browser2sw23sw__response__has__body(response)) {
    return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(_M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN6constrS1708);
  }
  const reader = _M0FP46f4ah6o3dsh7browser2sw20sw__response__reader(response);
  const _defer = () => {
    _M0FP46f4ah6o3dsh7browser2sw19sw__reader__release(reader);
  };
  const asset_bytes = new _M0TPB8MutLocalGiE(0);
  return _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__bodyN16_2aasync__driverS461(_env, new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2econsume__bounded__bodyL5State11_2awhile__2(bundle_bytes, reader, asset_bytes, _defer, _cont));
}
function _M0FP46f4ah6o3dsh7browser2sw37delete__generation__after__completionN16_2aasync__driverS545(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(undefined);
      }
      case 1: {
        const _State_1 = _state$2;
        const _err_cont = _State_1._3;
        const _cont = _State_1._2;
        const generation = _State_1._1;
        const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGbE(_M0FP46f4ah6o3dsh7browser2sw17sw__cache__delete(generation), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param) => {
          let _err;
          _L$2: {
            const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw37delete__generation__after__completionN16_2aasync__driverS545(new _M0DTP46f4ah6o3dsh7browser2sw85_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__generation__after__completion_2elambda_2f542L5State8State__0(_cont_param));
            let _bind$5;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _bind$5 = _ok._0;
            } else {
              const _err$2 = _bind$4;
              _err = _err$2._0;
              break _L$2;
            }
            if (_bind$5 === -1) {
              return;
            } else {
              const _Some = _bind$5;
              const _payload = _Some;
              _cont(_payload);
              return;
            }
          }
          _err_cont(_err);
        }, _err_cont);
        let _bind$4;
        if (_bind$3.$tag === 1) {
          const _ok = _bind$3;
          _bind$4 = _ok._0;
        } else {
          return _bind$3;
        }
        if (_bind$4 === -1) {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        } else {
          const _Some = _bind$4;
          const _payload = _Some;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw85_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__generation__after__completion_2elambda_2f542L5State8State__0(_payload);
          continue _L;
        }
      }
      default: {
        const _$42$try$47$258 = _state$2;
        const _err_cont$2 = _$42$try$47$258._3;
        const _cont$2 = _$42$try$47$258._2;
        const generation$2 = _$42$try$47$258._1;
        const _try_err = _$42$try$47$258._0;
        if (_try_err.$tag === 1) {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE3Err(_try_err);
        } else {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw85_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__generation__after__completion_2elambda_2f542L5State8State__1(false, generation$2, _cont$2, _err_cont$2);
          continue _L;
        }
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw37delete__generation__after__completion(work, generation) {
  _M0MP311moonbitlang5async9js__async7Promise11from__asyncGuE((_cont, _err_cont) => {
    let _err;
    _L: {
      const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGbE(work, _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw37delete__generation__after__completionN16_2aasync__driverS545(new _M0DTP46f4ah6o3dsh7browser2sw85_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__generation__after__completion_2elambda_2f542L5State8State__1(_cont_param, generation, _cont, _err_cont));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === -1) {
            return;
          } else {
            const _Some = _bind$5;
            const _payload = _Some;
            _cont(_payload);
            return;
          }
        }
        _err_cont(_err$2);
      }, (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw37delete__generation__after__completionN16_2aasync__driverS545(new _M0DTP46f4ah6o3dsh7browser2sw85_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__generation__after__completion_2elambda_2f542L5State12_2atry_2f258(_cont_param, generation, _cont, _err_cont));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === -1) {
            return;
          } else {
            const _Some = _bind$5;
            const _payload = _Some;
            _cont(_payload);
            return;
          }
        }
        _err_cont(_err$2);
      });
      let _bind$4;
      if (_bind$3.$tag === 1) {
        const _ok = _bind$3;
        _bind$4 = _ok._0;
      } else {
        const _err$2 = _bind$3;
        _err = _err$2._0;
        break _L;
      }
      if (_bind$4 === -1) {
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
      } else {
        const _Some = _bind$4;
        const _payload = _Some;
        return _M0FP46f4ah6o3dsh7browser2sw37delete__generation__after__completionN16_2aasync__driverS545(new _M0DTP46f4ah6o3dsh7browser2sw85_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__generation__after__completion_2elambda_2f542L5State8State__1(_payload, generation, _cont, _err_cont));
      }
    }
    return _M0FP46f4ah6o3dsh7browser2sw37delete__generation__after__completionN16_2aasync__driverS545(new _M0DTP46f4ah6o3dsh7browser2sw85_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__generation__after__completion_2elambda_2f542L5State12_2atry_2f258(_err, generation, _cont, _err_cont));
  }, _M0DTPC16option6OptionGRP311moonbitlang5async9js__async11AbortSignalE4None__);
}
function _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN16_2aasync__driverS581(constr, _state) {
  let _tmp$2 = _state;
  while (true) {
    const _state$2 = _tmp$2;
    if (_state$2.$tag === 0) {
      const _State_0 = _state$2;
      const _cont_param = _State_0._0;
      return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(_cont_param);
    } else {
      const _$42$try$47$263 = _state$2;
      const work = _$42$try$47$263._2;
      const generation = _$42$try$47$263._1;
      const _try_err = _$42$try$47$263._0;
      if (_try_err.$tag === 1) {
        return new _M0DTPC16result6ResultGObRPC15error5ErrorE3Err(_try_err);
      } else {
        _M0FP46f4ah6o3dsh7browser2sw37delete__generation__after__completion(work, generation);
        _tmp$2 = constr;
        continue;
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN16_2aasync__driverS585(_env, _state) {
  const constr = _env._4;
  const constr$2 = _env._3;
  const constr$3 = _env._2;
  const constr$4 = _env._1;
  const constr$5 = _env._0;
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _$42$try$47$268 = _state$2;
        const _try_err = _$42$try$47$268._0;
        if (_try_err.$tag === 1) {
          return new _M0DTPC16result6ResultGObRPC15error5ErrorE3Err(_try_err);
        } else {
          return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(constr$5);
        }
      }
      case 1: {
        return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(constr$3);
      }
      case 2: {
        const _State_2 = _state$2;
        const _err_cont = _State_2._6;
        const _cont = _State_2._5;
        const cached_response = _State_2._4;
        const origin = _State_2._3;
        const cache = _State_2._2;
        const asset = _State_2._1;
        const _cont_param = _State_2._0;
        if (!_cont_param) {
          return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(constr);
        }
        let _err;
        _L$2: {
          const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGuE(_M0FP46f4ah6o3dsh7browser2sw14sw__cache__put(cache, `${origin}${asset}`, cached_response), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$2) => {
            let _err$2;
            _L$3: {
              const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN16_2aasync__driverS585(_env, new _M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State8State__1(_cont_param$2));
              let _bind$5;
              if (_bind$4.$tag === 1) {
                const _ok = _bind$4;
                _bind$5 = _ok._0;
              } else {
                const _err$3 = _bind$4;
                _err$2 = _err$3._0;
                break _L$3;
              }
              if (_bind$5 === -1) {
                return;
              } else {
                const _Some = _bind$5;
                const _payload = _Some;
                _cont(_payload);
                return;
              }
            }
            _err_cont(_err$2);
          }, (_cont_param$2) => {
            let _err$2;
            _L$3: {
              const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN16_2aasync__driverS585(_env, new _M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State12_2atry_2f268(_cont_param$2));
              let _bind$5;
              if (_bind$4.$tag === 1) {
                const _ok = _bind$4;
                _bind$5 = _ok._0;
              } else {
                const _err$3 = _bind$4;
                _err$2 = _err$3._0;
                break _L$3;
              }
              if (_bind$5 === -1) {
                return;
              } else {
                const _Some = _bind$5;
                const _payload = _Some;
                _cont(_payload);
                return;
              }
            }
            _err_cont(_err$2);
          });
          let _bind$4;
          if (_bind$3.$tag === 1) {
            const _ok = _bind$3;
            _bind$4 = _ok._0;
          } else {
            const _err$2 = _bind$3;
            _err = _err$2._0;
            break _L$2;
          }
          if (_bind$4 === -1) {
            return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(-1);
          } else {
            const _Some = _bind$4;
            const _payload = _Some;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State8State__1(_payload);
            continue _L;
          }
        }
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State12_2atry_2f268(_err);
        continue _L;
      }
      case 3: {
        const _State_3 = _state$2;
        const _err_cont$2 = _State_3._8;
        const _cont$2 = _State_3._7;
        const request = _State_3._6;
        const expected_url = _State_3._5;
        const origin$2 = _State_3._4;
        const bundle_bytes = _State_3._3;
        const cache$2 = _State_3._2;
        const asset$2 = _State_3._1;
        const _cont_param$2 = _State_3._0;
        if (!_M0FP46f4ah6o3dsh7browser2sw30is__cacheable__shell__response(request, _cont_param$2, expected_url)) {
          return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(constr$2);
        }
        const cached_response$2 = _M0FP46f4ah6o3dsh7browser2sw19sw__response__clone(_cont_param$2);
        const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw22consume__bounded__body(_cont_param$2, bundle_bytes, (_cont_param$3) => {
          let _err$2;
          _L$3: {
            const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN16_2aasync__driverS585(_env, new _M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State8State__2(_cont_param$3, asset$2, cache$2, origin$2, cached_response$2, _cont$2, _err_cont$2));
            let _bind$5;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _bind$5 = _ok._0;
            } else {
              const _err$3 = _bind$4;
              _err$2 = _err$3._0;
              break _L$3;
            }
            if (_bind$5 === -1) {
              return;
            } else {
              const _Some = _bind$5;
              const _payload = _Some;
              _cont$2(_payload);
              return;
            }
          }
          _err_cont$2(_err$2);
        }, _err_cont$2);
        let _bind$4;
        if (_bind$3.$tag === 1) {
          const _ok = _bind$3;
          _bind$4 = _ok._0;
        } else {
          return _bind$3;
        }
        if (_bind$4 === -1) {
          return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(-1);
        } else {
          const _Some = _bind$4;
          const _payload = _Some;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State8State__2(_payload, asset$2, cache$2, origin$2, cached_response$2, _cont$2, _err_cont$2);
          continue _L;
        }
      }
      default: {
        const _$42$try$47$273 = _state$2;
        const _try_err$2 = _$42$try$47$273._0;
        if (_try_err$2.$tag === 1) {
          return new _M0DTPC16result6ResultGObRPC15error5ErrorE3Err(_try_err$2);
        } else {
          return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(constr$4);
        }
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__asset(asset, cache, generation, bundle_bytes, _cont, _err_cont) {
  const origin = _M0FP46f4ah6o3dsh7browser2sw20sw__location__origin();
  const expected_url = `${origin}${asset}`;
  const controller = _M0MP311moonbitlang5async9js__async15AbortController3new();
  const work = _M0MP311moonbitlang5async9js__async7Promise11from__asyncGbE((_cont$2, _err_cont$2) => {
    const _env = { _0: _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN6constrS1710, _1: _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN6constrS1714, _2: _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN6constrS1711, _3: _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN6constrS1713, _4: _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN6constrS1712 };
    const request = _M0FP46f4ah6o3dsh7browser2sw17sw__make__request(expected_url, "GET", "no-cache", "same-origin", "same-origin");
    let _err;
    _L: {
      const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(_M0FP46f4ah6o3dsh7browser2sw9sw__fetch(expected_url, "GET", "no-cache", "same-origin", "same-origin", _M0MP311moonbitlang5async9js__async15AbortController6signal(controller)), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN16_2aasync__driverS585(_env, new _M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State8State__3(_cont_param, asset, cache, bundle_bytes, origin, expected_url, request, _cont$2, _err_cont$2));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === -1) {
            return;
          } else {
            const _Some = _bind$5;
            const _payload = _Some;
            _cont$2(_payload);
            return;
          }
        }
        _err_cont$2(_err$2);
      }, (_cont_param) => {
        let _err$2;
        _L$2: {
          const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN16_2aasync__driverS585(_env, new _M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State12_2atry_2f273(_cont_param));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$3 = _bind$4;
            _err$2 = _err$3._0;
            break _L$2;
          }
          if (_bind$5 === -1) {
            return;
          } else {
            const _Some = _bind$5;
            const _payload = _Some;
            _cont$2(_payload);
            return;
          }
        }
        _err_cont$2(_err$2);
      });
      let _tmp$2;
      if (_bind$3.$tag === 1) {
        const _ok = _bind$3;
        _tmp$2 = _ok._0;
      } else {
        const _err$2 = _bind$3;
        _err = _err$2._0;
        break _L;
      }
      const _tmp$3 = _tmp$2;
      if (_tmp$3.$tag === 1) {
        const _Some = _tmp$3;
        const _payload = _Some._0;
        return _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN16_2aasync__driverS585(_env, new _M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State8State__3(_payload, asset, cache, bundle_bytes, origin, expected_url, request, _cont$2, _err_cont$2));
      } else {
        return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(-1);
      }
    }
    return _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN16_2aasync__driverS585(_env, new _M0DTP46f4ah6o3dsh7browser2sw75_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__asset_2efn_2f582L5State12_2atry_2f273(_err));
  }, _M0DTPC16option6OptionGRP311moonbitlang5async9js__async11AbortSignalE4None__);
  let _err;
  _L: {
    const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGbE(_M0FP46f4ah6o3dsh7browser2sw17sw__with__timeout(work, 10000, `Timed out fetching shell asset: ${asset}`, () => {
      _M0MP311moonbitlang5async9js__async15AbortController5abort(controller);
    }), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param) => {
      let _err$2;
      _L$2: {
        const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN16_2aasync__driverS581(_M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN6constrS1709, new _M0DTP46f4ah6o3dsh7browser2sw64_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__assetL5State8State__0(_cont_param));
        let _bind$5;
        if (_bind$4.$tag === 1) {
          const _ok = _bind$4;
          _bind$5 = _ok._0;
        } else {
          const _err$3 = _bind$4;
          _err$2 = _err$3._0;
          break _L$2;
        }
        if (_bind$5 === -1) {
          return;
        } else {
          const _Some = _bind$5;
          const _payload = _Some;
          _cont(_payload);
          return;
        }
      }
      _err_cont(_err$2);
    }, (_cont_param) => {
      let _err$2;
      _L$2: {
        const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN16_2aasync__driverS581(_M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN6constrS1709, new _M0DTP46f4ah6o3dsh7browser2sw64_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__assetL5State12_2atry_2f263(_cont_param, generation, work));
        let _bind$5;
        if (_bind$4.$tag === 1) {
          const _ok = _bind$4;
          _bind$5 = _ok._0;
        } else {
          const _err$3 = _bind$4;
          _err$2 = _err$3._0;
          break _L$2;
        }
        if (_bind$5 === -1) {
          return;
        } else {
          const _Some = _bind$5;
          const _payload = _Some;
          _cont(_payload);
          return;
        }
      }
      _err_cont(_err$2);
    });
    let _bind$4;
    if (_bind$3.$tag === 1) {
      const _ok = _bind$3;
      _bind$4 = _ok._0;
    } else {
      const _err$2 = _bind$3;
      _err = _err$2._0;
      break _L;
    }
    if (_bind$4 === -1) {
      return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(-1);
    } else {
      const _Some = _bind$4;
      const _payload = _Some;
      return _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN16_2aasync__driverS581(_M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN6constrS1709, new _M0DTP46f4ah6o3dsh7browser2sw64_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__assetL5State8State__0(_payload));
    }
  }
  return _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN16_2aasync__driverS581(_M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__assetN6constrS1709, new _M0DTP46f4ah6o3dsh7browser2sw64_24f4ah6o_2fdsh_2fbrowser_2fsw_2efetch__and__cache__shell__assetL5State12_2atry_2f263(_err, generation, work));
}
function _M0FP46f4ah6o3dsh7browser2sw15metadata__cache(_cont, _err_cont) {
  return _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(_M0FP46f4ah6o3dsh7browser2sw15sw__cache__open(_M0FP46f4ah6o3dsh7browser2sw17meta__cache__name), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, _cont, _err_cont);
}
function _M0FP46f4ah6o3dsh7browser2sw14read__metadataN16_2aasync__driverS671(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _State_0 = _state$2;
        const _cont_param = _State_0._0;
        return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(_cont_param));
      }
      case 1: {
        const _State_1 = _state$2;
        const _err_cont = _State_1._2;
        const _cont = _State_1._1;
        const _cont_param$2 = _State_1._0;
        const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGsE(_M0FP46f4ah6o3dsh7browser2sw18sw__response__text(_cont_param$2), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$3) => {
          let _err;
          _L$2: {
            const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw14read__metadataN16_2aasync__driverS671(new _M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__0(_cont_param$3));
            let _tmp$3;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _tmp$3 = _ok._0;
            } else {
              const _err$2 = _bind$4;
              _err = _err$2._0;
              break _L$2;
            }
            const _tmp$4 = _tmp$3;
            if (_tmp$4.$tag === 1) {
              const _Some = _tmp$4;
              const _payload = _Some._0;
              _cont(_payload);
              return;
            } else {
              return;
            }
          }
          _err_cont(_err);
        }, _err_cont);
        let _bind$4;
        if (_bind$3.$tag === 1) {
          const _ok = _bind$3;
          _bind$4 = _ok._0;
        } else {
          return _bind$3;
        }
        if (_bind$4 === undefined) {
          return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
        } else {
          const _Some = _bind$4;
          const _payload = _Some;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__0(_payload);
          continue _L;
        }
      }
      case 2: {
        const _State_2 = _state$2;
        const _err_cont$2 = _State_2._4;
        const _cont$2 = _State_2._3;
        const cache = _State_2._2;
        const key = _State_2._1;
        const _cont_param$3 = _State_2._0;
        if (_cont_param$3) {
          const _bind$5 = _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(_M0FP46f4ah6o3dsh7browser2sw16sw__cache__match(cache, key), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$4) => {
            let _err;
            _L$2: {
              const _bind$6 = _M0FP46f4ah6o3dsh7browser2sw14read__metadataN16_2aasync__driverS671(new _M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__1(_cont_param$4, _cont$2, _err_cont$2));
              let _tmp$3;
              if (_bind$6.$tag === 1) {
                const _ok = _bind$6;
                _tmp$3 = _ok._0;
              } else {
                const _err$2 = _bind$6;
                _err = _err$2._0;
                break _L$2;
              }
              const _tmp$4 = _tmp$3;
              if (_tmp$4.$tag === 1) {
                const _Some = _tmp$4;
                const _payload = _Some._0;
                _cont$2(_payload);
                return;
              } else {
                return;
              }
            }
            _err_cont$2(_err);
          }, _err_cont$2);
          let _tmp$3;
          if (_bind$5.$tag === 1) {
            const _ok = _bind$5;
            _tmp$3 = _ok._0;
          } else {
            return _bind$5;
          }
          const _tmp$4 = _tmp$3;
          if (_tmp$4.$tag === 1) {
            const _Some = _tmp$4;
            const _payload = _Some._0;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__1(_payload, _cont$2, _err_cont$2);
            continue _L;
          } else {
            return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
          }
        } else {
          return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(undefined));
        }
      }
      default: {
        const _State_3 = _state$2;
        const _err_cont$3 = _State_3._3;
        const _cont$3 = _State_3._2;
        const key$2 = _State_3._1;
        const _cont_param$4 = _State_3._0;
        const _bind$5 = _M0MP311moonbitlang5async9js__async7Promise4waitGbE(_M0FP46f4ah6o3dsh7browser2sw14sw__cache__has(_cont_param$4, key$2), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$5) => {
          let _err;
          _L$2: {
            const _bind$6 = _M0FP46f4ah6o3dsh7browser2sw14read__metadataN16_2aasync__driverS671(new _M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__2(_cont_param$5, key$2, _cont_param$4, _cont$3, _err_cont$3));
            let _tmp$3;
            if (_bind$6.$tag === 1) {
              const _ok = _bind$6;
              _tmp$3 = _ok._0;
            } else {
              const _err$2 = _bind$6;
              _err = _err$2._0;
              break _L$2;
            }
            const _tmp$4 = _tmp$3;
            if (_tmp$4.$tag === 1) {
              const _Some = _tmp$4;
              const _payload = _Some._0;
              _cont$3(_payload);
              return;
            } else {
              return;
            }
          }
          _err_cont$3(_err);
        }, _err_cont$3);
        let _bind$6;
        if (_bind$5.$tag === 1) {
          const _ok = _bind$5;
          _bind$6 = _ok._0;
        } else {
          return _bind$5;
        }
        if (_bind$6 === -1) {
          return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
        } else {
          const _Some = _bind$6;
          const _payload = _Some;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__2(_payload, key$2, _cont_param$4, _cont$3, _err_cont$3);
          continue _L;
        }
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw14read__metadata(key, _cont, _err_cont) {
  const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw15metadata__cache((_cont_param) => {
    let _err;
    _L: {
      const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw14read__metadataN16_2aasync__driverS671(new _M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__3(_cont_param, key, _cont, _err_cont));
      let _tmp$2;
      if (_bind$4.$tag === 1) {
        const _ok = _bind$4;
        _tmp$2 = _ok._0;
      } else {
        const _err$2 = _bind$4;
        _err = _err$2._0;
        break _L;
      }
      const _tmp$3 = _tmp$2;
      if (_tmp$3.$tag === 1) {
        const _Some = _tmp$3;
        const _payload = _Some._0;
        _cont(_payload);
        return;
      } else {
        return;
      }
    }
    _err_cont(_err);
  }, _err_cont);
  let _tmp$2;
  if (_bind$3.$tag === 1) {
    const _ok = _bind$3;
    _tmp$2 = _ok._0;
  } else {
    return _bind$3;
  }
  const _tmp$3 = _tmp$2;
  if (_tmp$3.$tag === 1) {
    const _Some = _tmp$3;
    const _payload = _Some._0;
    return _M0FP46f4ah6o3dsh7browser2sw14read__metadataN16_2aasync__driverS671(new _M0DTP46f4ah6o3dsh7browser2sw47_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__metadataL5State8State__3(_payload, key, _cont, _err_cont));
  } else {
    return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
  }
}
function _M0FP46f4ah6o3dsh7browser2sw15write__metadataN16_2aasync__driverS720(_env, _state) {
  const constr = _env._1;
  const constr$2 = _env._0;
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _$42$try$47$278 = _state$2;
        const _try_err = _$42$try$47$278._0;
        if (_try_err.$tag === 1) {
          return new _M0DTPC16result6ResultGObRPC15error5ErrorE3Err(_try_err);
        } else {
          return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(constr);
        }
      }
      case 1: {
        return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(constr$2);
      }
      default: {
        const _State_2 = _state$2;
        const _err_cont = _State_2._4;
        const _cont = _State_2._3;
        const value = _State_2._2;
        const key = _State_2._1;
        const _cont_param = _State_2._0;
        let _err;
        _L$2: {
          const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGuE(_M0FP46f4ah6o3dsh7browser2sw14sw__cache__put(_cont_param, key, _M0FP46f4ah6o3dsh7browser2sw18sw__text__response(value, _M0FP46f4ah6o3dsh7browser2sw19text__content__type)), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$2) => {
            let _err$2;
            _L$3: {
              const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw15write__metadataN16_2aasync__driverS720(_env, new _M0DTP46f4ah6o3dsh7browser2sw48_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewrite__metadataL5State8State__1(_cont_param$2));
              let _bind$5;
              if (_bind$4.$tag === 1) {
                const _ok = _bind$4;
                _bind$5 = _ok._0;
              } else {
                const _err$3 = _bind$4;
                _err$2 = _err$3._0;
                break _L$3;
              }
              if (_bind$5 === -1) {
                return;
              } else {
                const _Some = _bind$5;
                const _payload = _Some;
                _cont(_payload);
                return;
              }
            }
            _err_cont(_err$2);
          }, (_cont_param$2) => {
            let _err$2;
            _L$3: {
              const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw15write__metadataN16_2aasync__driverS720(_env, new _M0DTP46f4ah6o3dsh7browser2sw48_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewrite__metadataL5State12_2atry_2f278(_cont_param$2));
              let _bind$5;
              if (_bind$4.$tag === 1) {
                const _ok = _bind$4;
                _bind$5 = _ok._0;
              } else {
                const _err$3 = _bind$4;
                _err$2 = _err$3._0;
                break _L$3;
              }
              if (_bind$5 === -1) {
                return;
              } else {
                const _Some = _bind$5;
                const _payload = _Some;
                _cont(_payload);
                return;
              }
            }
            _err_cont(_err$2);
          });
          let _bind$4;
          if (_bind$3.$tag === 1) {
            const _ok = _bind$3;
            _bind$4 = _ok._0;
          } else {
            const _err$2 = _bind$3;
            _err = _err$2._0;
            break _L$2;
          }
          if (_bind$4 === -1) {
            return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(-1);
          } else {
            const _Some = _bind$4;
            const _payload = _Some;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw48_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewrite__metadataL5State8State__1(_payload);
            continue _L;
          }
        }
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw48_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewrite__metadataL5State12_2atry_2f278(_err);
        continue _L;
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw15write__metadata(key, value, _cont, _err_cont) {
  const _env = { _0: _M0FP46f4ah6o3dsh7browser2sw15write__metadataN6constrS1716, _1: _M0FP46f4ah6o3dsh7browser2sw15write__metadataN6constrS1715 };
  const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw15metadata__cache((_cont_param) => {
    let _err;
    _L: {
      const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw15write__metadataN16_2aasync__driverS720(_env, new _M0DTP46f4ah6o3dsh7browser2sw48_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewrite__metadataL5State8State__2(_cont_param, key, value, _cont, _err_cont));
      let _bind$5;
      if (_bind$4.$tag === 1) {
        const _ok = _bind$4;
        _bind$5 = _ok._0;
      } else {
        const _err$2 = _bind$4;
        _err = _err$2._0;
        break _L;
      }
      if (_bind$5 === -1) {
        return;
      } else {
        const _Some = _bind$5;
        const _payload = _Some;
        _cont(_payload);
        return;
      }
    }
    _err_cont(_err);
  }, _err_cont);
  let _tmp$2;
  if (_bind$3.$tag === 1) {
    const _ok = _bind$3;
    _tmp$2 = _ok._0;
  } else {
    return _bind$3;
  }
  const _tmp$3 = _tmp$2;
  if (_tmp$3.$tag === 1) {
    const _Some = _tmp$3;
    const _payload = _Some._0;
    return _M0FP46f4ah6o3dsh7browser2sw15write__metadataN16_2aasync__driverS720(_env, new _M0DTP46f4ah6o3dsh7browser2sw48_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewrite__metadataL5State8State__2(_payload, key, value, _cont, _err_cont));
  } else {
    return new _M0DTPC16result6ResultGObRPC15error5ErrorE2Ok(-1);
  }
}
function _M0FP46f4ah6o3dsh7browser2sw16delete__metadataN16_2aasync__driverS754(_state) {
  let _tmp$2 = _state;
  while (true) {
    const _state$2 = _tmp$2;
    if (_state$2.$tag === 0) {
      return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(undefined);
    } else {
      const _State_1 = _state$2;
      const _err_cont = _State_1._3;
      const _cont = _State_1._2;
      const key = _State_1._1;
      const _cont_param = _State_1._0;
      const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGbE(_M0FP46f4ah6o3dsh7browser2sw22sw__cache__delete__key(_cont_param, key), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$2) => {
        let _err;
        _L: {
          const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw16delete__metadataN16_2aasync__driverS754(new _M0DTP46f4ah6o3dsh7browser2sw49_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__metadataL5State8State__0(_cont_param$2));
          let _bind$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _bind$5 = _ok._0;
          } else {
            const _err$2 = _bind$4;
            _err = _err$2._0;
            break _L;
          }
          if (_bind$5 === -1) {
            return;
          } else {
            const _Some = _bind$5;
            const _payload = _Some;
            _cont(_payload);
            return;
          }
        }
        _err_cont(_err);
      }, _err_cont);
      let _bind$4;
      if (_bind$3.$tag === 1) {
        const _ok = _bind$3;
        _bind$4 = _ok._0;
      } else {
        return _bind$3;
      }
      if (_bind$4 === -1) {
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
      } else {
        const _Some = _bind$4;
        const _payload = _Some;
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw49_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__metadataL5State8State__0(_payload);
        continue;
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw16delete__metadata(key, _cont, _err_cont) {
  const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw15metadata__cache((_cont_param) => {
    let _err;
    _L: {
      const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw16delete__metadataN16_2aasync__driverS754(new _M0DTP46f4ah6o3dsh7browser2sw49_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__metadataL5State8State__1(_cont_param, key, _cont, _err_cont));
      let _bind$5;
      if (_bind$4.$tag === 1) {
        const _ok = _bind$4;
        _bind$5 = _ok._0;
      } else {
        const _err$2 = _bind$4;
        _err = _err$2._0;
        break _L;
      }
      if (_bind$5 === -1) {
        return;
      } else {
        const _Some = _bind$5;
        const _payload = _Some;
        _cont(_payload);
        return;
      }
    }
    _err_cont(_err);
  }, _err_cont);
  let _tmp$2;
  if (_bind$3.$tag === 1) {
    const _ok = _bind$3;
    _tmp$2 = _ok._0;
  } else {
    return _bind$3;
  }
  const _tmp$3 = _tmp$2;
  if (_tmp$3.$tag === 1) {
    const _Some = _tmp$3;
    const _payload = _Some._0;
    return _M0FP46f4ah6o3dsh7browser2sw16delete__metadataN16_2aasync__driverS754(new _M0DTP46f4ah6o3dsh7browser2sw49_24f4ah6o_2fdsh_2fbrowser_2fsw_2edelete__metadataL5State8State__1(_payload, key, _cont, _err_cont));
  } else {
    return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
  }
}
function _M0FP46f4ah6o3dsh7browser2sw24read__active__generationN16_2aasync__driverS779(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(undefined));
      }
      case 1: {
        const _State_1 = _state$2;
        const name = _State_1._1;
        const _cont_param = _State_1._0;
        return _M0MPC15array5Array8containsGsE(_cont_param, name) ? new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(name)) : new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(undefined));
      }
      default: {
        const _State_2 = _state$2;
        const _err_cont = _State_2._2;
        const _cont = _State_2._1;
        const _cont_param$2 = _State_2._0;
        if (_cont_param$2 === undefined) {
          _tmp$2 = _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__active__generationL5State12_2aarm_2f284__;
          continue _L;
        } else {
          const _Some = _cont_param$2;
          const _name = _Some;
          if (_M0FP46f4ah6o3dsh7browser2sw20is__generation__name(_name)) {
            const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(_M0FP46f4ah6o3dsh7browser2sw16sw__cache__names(), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$3) => {
              let _err;
              _L$2: {
                const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw24read__active__generationN16_2aasync__driverS779(new _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__active__generationL5State8State__1(_cont_param$3, _name));
                let _tmp$3;
                if (_bind$4.$tag === 1) {
                  const _ok = _bind$4;
                  _tmp$3 = _ok._0;
                } else {
                  const _err$2 = _bind$4;
                  _err = _err$2._0;
                  break _L$2;
                }
                const _tmp$4 = _tmp$3;
                if (_tmp$4.$tag === 1) {
                  const _Some$2 = _tmp$4;
                  const _payload = _Some$2._0;
                  _cont(_payload);
                  return;
                } else {
                  return;
                }
              }
              _err_cont(_err);
            }, _err_cont);
            let _tmp$3;
            if (_bind$3.$tag === 1) {
              const _ok = _bind$3;
              _tmp$3 = _ok._0;
            } else {
              return _bind$3;
            }
            const _tmp$4 = _tmp$3;
            if (_tmp$4.$tag === 1) {
              const _Some$2 = _tmp$4;
              const _payload = _Some$2._0;
              _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__active__generationL5State8State__1(_payload, _name);
              continue _L;
            } else {
              return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
            }
          } else {
            _tmp$2 = _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__active__generationL5State12_2aarm_2f284__;
            continue _L;
          }
        }
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw24read__active__generation(_cont, _err_cont) {
  const origin = _M0FP46f4ah6o3dsh7browser2sw20sw__location__origin();
  const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw14read__metadata(`${origin}${_M0FP46f4ah6o3dsh7browser2sw11active__key}`, (_cont_param) => {
    let _err;
    _L: {
      const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw24read__active__generationN16_2aasync__driverS779(new _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__active__generationL5State8State__2(_cont_param, _cont, _err_cont));
      let _tmp$2;
      if (_bind$4.$tag === 1) {
        const _ok = _bind$4;
        _tmp$2 = _ok._0;
      } else {
        const _err$2 = _bind$4;
        _err = _err$2._0;
        break _L;
      }
      const _tmp$3 = _tmp$2;
      if (_tmp$3.$tag === 1) {
        const _Some = _tmp$3;
        const _payload = _Some._0;
        _cont(_payload);
        return;
      } else {
        return;
      }
    }
    _err_cont(_err);
  }, _err_cont);
  let _tmp$2;
  if (_bind$3.$tag === 1) {
    const _ok = _bind$3;
    _tmp$2 = _ok._0;
  } else {
    return _bind$3;
  }
  const _tmp$3 = _tmp$2;
  if (_tmp$3.$tag === 1) {
    const _Some = _tmp$3;
    const _payload = _Some._0;
    return _M0FP46f4ah6o3dsh7browser2sw24read__active__generationN16_2aasync__driverS779(new _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__active__generationL5State8State__2(_payload, _cont, _err_cont));
  } else {
    return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
  }
}
function _M0FP46f4ah6o3dsh7browser2sw24read__client__generationN16_2aasync__driverS804(_state) {
  let _tmp$2 = _state;
  while (true) {
    const _state$2 = _tmp$2;
    if (_state$2.$tag === 0) {
      return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(undefined));
    } else {
      const _State_1 = _state$2;
      const _cont_param = _State_1._0;
      if (_cont_param === undefined) {
        _tmp$2 = _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__client__generationL5State12_2aarm_2f289__;
        continue;
      } else {
        const _Some = _cont_param;
        const _name = _Some;
        if (_M0FP46f4ah6o3dsh7browser2sw20is__generation__name(_name)) {
          return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(_name));
        } else {
          _tmp$2 = _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__client__generationL5State12_2aarm_2f289__;
          continue;
        }
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw24read__client__generation(client_id, _cont, _err_cont) {
  if (client_id === "") {
    return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(undefined));
  }
  const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw14read__metadata(_M0FP46f4ah6o3dsh7browser2sw22encoded__metadata__key(_M0FP46f4ah6o3dsh7browser2sw20sw__location__origin(), _M0FP46f4ah6o3dsh7browser2sw19client__pin__prefix, client_id), (_cont_param) => {
    let _err;
    _L: {
      const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw24read__client__generationN16_2aasync__driverS804(new _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__client__generationL5State8State__1(_cont_param));
      let _tmp$2;
      if (_bind$4.$tag === 1) {
        const _ok = _bind$4;
        _tmp$2 = _ok._0;
      } else {
        const _err$2 = _bind$4;
        _err = _err$2._0;
        break _L;
      }
      const _tmp$3 = _tmp$2;
      if (_tmp$3.$tag === 1) {
        const _Some = _tmp$3;
        const _payload = _Some._0;
        _cont(_payload);
        return;
      } else {
        return;
      }
    }
    _err_cont(_err);
  }, _err_cont);
  let _tmp$2;
  if (_bind$3.$tag === 1) {
    const _ok = _bind$3;
    _tmp$2 = _ok._0;
  } else {
    return _bind$3;
  }
  const _tmp$3 = _tmp$2;
  if (_tmp$3.$tag === 1) {
    const _Some = _tmp$3;
    const _payload = _Some._0;
    return _M0FP46f4ah6o3dsh7browser2sw24read__client__generationN16_2aasync__driverS804(new _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2eread__client__generationL5State8State__1(_payload));
  } else {
    return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
  }
}
function _M0FP46f4ah6o3dsh7browser2sw25create__shell__generationN16_2aasync__driverS817(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _State_0 = _state$2;
        const generation = _State_0._1;
        return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(generation));
      }
      case 1: {
        return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(undefined));
      }
      case 2: {
        const _State_2 = _state$2;
        const _err_cont = _State_2._3;
        const _cont = _State_2._2;
        const staging_key = _State_2._1;
        const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw16delete__metadata(staging_key, (_cont_param) => {
          let _err;
          _L$2: {
            const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw25create__shell__generationN16_2aasync__driverS817(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__1(_cont_param));
            let _tmp$3;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _tmp$3 = _ok._0;
            } else {
              const _err$2 = _bind$4;
              _err = _err$2._0;
              break _L$2;
            }
            const _tmp$4 = _tmp$3;
            if (_tmp$4.$tag === 1) {
              const _Some = _tmp$4;
              const _payload = _Some._0;
              _cont(_payload);
              return;
            } else {
              return;
            }
          }
          _err_cont(_err);
        }, _err_cont);
        let _bind$4;
        if (_bind$3.$tag === 1) {
          const _ok = _bind$3;
          _bind$4 = _ok._0;
        } else {
          return _bind$3;
        }
        if (_bind$4 === -1) {
          return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
        } else {
          const _Some = _bind$4;
          const _payload = _Some;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__1(_payload);
          continue _L;
        }
      }
      case 3: {
        const _State_3 = _state$2;
        const _err_cont$2 = _State_3._5;
        const _cont$2 = _State_3._4;
        const complete = _State_3._3;
        const staging_key$2 = _State_3._2;
        const generation$2 = _State_3._1;
        if (!complete.val) {
          const _bind$5 = _M0MP311moonbitlang5async9js__async7Promise4waitGbE(_M0FP46f4ah6o3dsh7browser2sw17sw__cache__delete(generation$2), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param) => {
            let _err;
            _L$2: {
              const _bind$6 = _M0FP46f4ah6o3dsh7browser2sw25create__shell__generationN16_2aasync__driverS817(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__2(_cont_param, staging_key$2, _cont$2, _err_cont$2));
              let _tmp$3;
              if (_bind$6.$tag === 1) {
                const _ok = _bind$6;
                _tmp$3 = _ok._0;
              } else {
                const _err$2 = _bind$6;
                _err = _err$2._0;
                break _L$2;
              }
              const _tmp$4 = _tmp$3;
              if (_tmp$4.$tag === 1) {
                const _Some = _tmp$4;
                const _payload = _Some._0;
                _cont$2(_payload);
                return;
              } else {
                return;
              }
            }
            _err_cont$2(_err);
          }, _err_cont$2);
          let _bind$6;
          if (_bind$5.$tag === 1) {
            const _ok = _bind$5;
            _bind$6 = _ok._0;
          } else {
            return _bind$5;
          }
          if (_bind$6 === -1) {
            return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
          } else {
            const _Some = _bind$6;
            const _payload = _Some;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__2(_payload, staging_key$2, _cont$2, _err_cont$2);
            continue _L;
          }
        } else {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__0(undefined, generation$2);
          continue _L;
        }
      }
      case 4: {
        const _$42$for_4 = _state$2;
        const _err_cont$3 = _$42$for_4._7;
        const _cont$3 = _$42$for_4._6;
        const _it = _$42$for_4._5;
        const complete$2 = _$42$for_4._4;
        const bundle_bytes = _$42$for_4._3;
        const cache = _$42$for_4._2;
        const staging_key$3 = _$42$for_4._1;
        const generation$3 = _$42$for_4._0;
        const _bind$5 = _M0MPB4Iter4nextGRP411moonbitlang5async8internal9coroutine9CoroutineE(_it);
        if (_bind$5 === undefined) {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__3(undefined, generation$3, staging_key$3, complete$2, _cont$3, _err_cont$3);
          continue _L;
        } else {
          const _Some = _bind$5;
          const _asset = _Some;
          const _bind$6 = _M0FP46f4ah6o3dsh7browser2sw31fetch__and__cache__shell__asset(_asset, cache, generation$3, bundle_bytes, (_cont_param) => {
            let _err;
            _L$2: {
              const _bind$7 = _M0FP46f4ah6o3dsh7browser2sw25create__shell__generationN16_2aasync__driverS817(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__5(_cont_param, generation$3, staging_key$3, cache, bundle_bytes, complete$2, _it, _cont$3, _err_cont$3));
              let _tmp$3;
              if (_bind$7.$tag === 1) {
                const _ok = _bind$7;
                _tmp$3 = _ok._0;
              } else {
                const _err$2 = _bind$7;
                _err = _err$2._0;
                break _L$2;
              }
              const _tmp$4 = _tmp$3;
              if (_tmp$4.$tag === 1) {
                const _Some$2 = _tmp$4;
                const _payload = _Some$2._0;
                _cont$3(_payload);
                return;
              } else {
                return;
              }
            }
            _err_cont$3(_err);
          }, _err_cont$3);
          let _bind$7;
          if (_bind$6.$tag === 1) {
            const _ok = _bind$6;
            _bind$7 = _ok._0;
          } else {
            return _bind$6;
          }
          if (_bind$7 === -1) {
            return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
          } else {
            const _Some$2 = _bind$7;
            const _payload = _Some$2;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__5(_payload, generation$3, staging_key$3, cache, bundle_bytes, complete$2, _it, _cont$3, _err_cont$3);
            continue _L;
          }
        }
      }
      case 5: {
        const _State_5 = _state$2;
        const _err_cont$4 = _State_5._8;
        const _cont$4 = _State_5._7;
        const _it$2 = _State_5._6;
        const complete$3 = _State_5._5;
        const bundle_bytes$2 = _State_5._4;
        const cache$2 = _State_5._3;
        const staging_key$4 = _State_5._2;
        const generation$4 = _State_5._1;
        const _cont_param = _State_5._0;
        if (!_cont_param) {
          complete$3.val = false;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__3(undefined, generation$4, staging_key$4, complete$3, _cont$4, _err_cont$4);
          continue _L;
        }
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State9_2afor__4(generation$4, staging_key$4, cache$2, bundle_bytes$2, complete$3, _it$2, _cont$4, _err_cont$4);
        continue _L;
      }
      case 6: {
        const _State_6 = _state$2;
        const _err_cont$5 = _State_6._4;
        const _cont$5 = _State_6._3;
        const staging_key$5 = _State_6._2;
        const generation$5 = _State_6._1;
        const _cont_param$2 = _State_6._0;
        const bundle_bytes$3 = _M0MPC13ref3Ref3RefGiE(0);
        const complete$4 = new _M0TPB8MutLocalGbE(true);
        const _it$3 = _M0MPC15array13ReadOnlyArray4iterGsE(_M0FP46f4ah6o3dsh7browser2sw13shell__assets);
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State9_2afor__4(generation$5, staging_key$5, _cont_param$2, bundle_bytes$3, complete$4, _it$3, _cont$5, _err_cont$5);
        continue _L;
      }
      case 7: {
        return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(undefined));
      }
      case 8: {
        const _$42$try$47$305 = _state$2;
        const _err_cont$6 = _$42$try$47$305._3;
        const _cont$6 = _$42$try$47$305._2;
        const staging_key$6 = _$42$try$47$305._1;
        const _try_err = _$42$try$47$305._0;
        if (_try_err.$tag === 1) {
          return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE3Err(_try_err);
        } else {
          const _bind$6 = _M0FP46f4ah6o3dsh7browser2sw16delete__metadata(staging_key$6, (_cont_param$3) => {
            let _err;
            _L$2: {
              const _bind$7 = _M0FP46f4ah6o3dsh7browser2sw25create__shell__generationN16_2aasync__driverS817(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__7(_cont_param$3));
              let _tmp$3;
              if (_bind$7.$tag === 1) {
                const _ok = _bind$7;
                _tmp$3 = _ok._0;
              } else {
                const _err$2 = _bind$7;
                _err = _err$2._0;
                break _L$2;
              }
              const _tmp$4 = _tmp$3;
              if (_tmp$4.$tag === 1) {
                const _Some = _tmp$4;
                const _payload = _Some._0;
                _cont$6(_payload);
                return;
              } else {
                return;
              }
            }
            _err_cont$6(_err);
          }, _err_cont$6);
          let _bind$7;
          if (_bind$6.$tag === 1) {
            const _ok = _bind$6;
            _bind$7 = _ok._0;
          } else {
            return _bind$6;
          }
          if (_bind$7 === -1) {
            return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
          } else {
            const _Some = _bind$7;
            const _payload = _Some;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__7(_payload);
            continue _L;
          }
        }
      }
      default: {
        const _State_9 = _state$2;
        const _err_cont$7 = _State_9._4;
        const _cont$7 = _State_9._3;
        const staging_key$7 = _State_9._2;
        const generation$6 = _State_9._1;
        const _cont_param$3 = _State_9._0;
        if (!_cont_param$3) {
          return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(undefined));
        }
        let _err;
        _L$2: {
          const _bind$6 = _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(_M0FP46f4ah6o3dsh7browser2sw15sw__cache__open(generation$6), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$4) => {
            let _err$2;
            _L$3: {
              const _bind$7 = _M0FP46f4ah6o3dsh7browser2sw25create__shell__generationN16_2aasync__driverS817(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__6(_cont_param$4, generation$6, staging_key$7, _cont$7, _err_cont$7));
              let _tmp$3;
              if (_bind$7.$tag === 1) {
                const _ok = _bind$7;
                _tmp$3 = _ok._0;
              } else {
                const _err$3 = _bind$7;
                _err$2 = _err$3._0;
                break _L$3;
              }
              const _tmp$4 = _tmp$3;
              if (_tmp$4.$tag === 1) {
                const _Some = _tmp$4;
                const _payload = _Some._0;
                _cont$7(_payload);
                return;
              } else {
                return;
              }
            }
            _err_cont$7(_err$2);
          }, (_cont_param$4) => {
            let _err$2;
            _L$3: {
              const _bind$7 = _M0FP46f4ah6o3dsh7browser2sw25create__shell__generationN16_2aasync__driverS817(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State12_2atry_2f305(_cont_param$4, staging_key$7, _cont$7, _err_cont$7));
              let _tmp$3;
              if (_bind$7.$tag === 1) {
                const _ok = _bind$7;
                _tmp$3 = _ok._0;
              } else {
                const _err$3 = _bind$7;
                _err$2 = _err$3._0;
                break _L$3;
              }
              const _tmp$4 = _tmp$3;
              if (_tmp$4.$tag === 1) {
                const _Some = _tmp$4;
                const _payload = _Some._0;
                _cont$7(_payload);
                return;
              } else {
                return;
              }
            }
            _err_cont$7(_err$2);
          });
          let _tmp$3;
          if (_bind$6.$tag === 1) {
            const _ok = _bind$6;
            _tmp$3 = _ok._0;
          } else {
            const _err$2 = _bind$6;
            _err = _err$2._0;
            break _L$2;
          }
          const _tmp$4 = _tmp$3;
          if (_tmp$4.$tag === 1) {
            const _Some = _tmp$4;
            const _payload = _Some._0;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__6(_payload, generation$6, staging_key$7, _cont$7, _err_cont$7);
            continue _L;
          } else {
            return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
          }
        }
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State12_2atry_2f305(_err, staging_key$7, _cont$7, _err_cont$7);
        continue _L;
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw25create__shell__generation(_cont, _err_cont) {
  _M0FP46f4ah6o3dsh7browser2sw19generation__counter.val = _M0FP46f4ah6o3dsh7browser2sw19generation__counter.val + 1 | 0;
  const generation = `${_M0FP46f4ah6o3dsh7browser2sw18generation__prefix}${_M0FP46f4ah6o3dsh7browser2sw21sw__generation__nonce()}-${_M0MPC13int3Int18to__string_2einner(_M0FP46f4ah6o3dsh7browser2sw19generation__counter.val, 10)}`;
  const origin = _M0FP46f4ah6o3dsh7browser2sw20sw__location__origin();
  const staging_key = _M0FP46f4ah6o3dsh7browser2sw22encoded__metadata__key(origin, _M0FP46f4ah6o3dsh7browser2sw15staging__prefix, generation);
  const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw15write__metadata(staging_key, "1", (_cont_param) => {
    let _err;
    _L: {
      const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw25create__shell__generationN16_2aasync__driverS817(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__9(_cont_param, generation, staging_key, _cont, _err_cont));
      let _tmp$2;
      if (_bind$4.$tag === 1) {
        const _ok = _bind$4;
        _tmp$2 = _ok._0;
      } else {
        const _err$2 = _bind$4;
        _err = _err$2._0;
        break _L;
      }
      const _tmp$3 = _tmp$2;
      if (_tmp$3.$tag === 1) {
        const _Some = _tmp$3;
        const _payload = _Some._0;
        _cont(_payload);
        return;
      } else {
        return;
      }
    }
    _err_cont(_err);
  }, _err_cont);
  let _bind$4;
  if (_bind$3.$tag === 1) {
    const _ok = _bind$3;
    _bind$4 = _ok._0;
  } else {
    return _bind$3;
  }
  if (_bind$4 === -1) {
    return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
  } else {
    const _Some = _bind$4;
    const _payload = _Some;
    return _M0FP46f4ah6o3dsh7browser2sw25create__shell__generationN16_2aasync__driverS817(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecreate__shell__generationL5State8State__9(_payload, generation, staging_key, _cont, _err_cont));
  }
}
function _M0FP46f4ah6o3dsh7browser2sw24find__legacy__generationN16_2aasync__driverS924(_state) {
  const _State_0 = _state;
  const _cont_param = _State_0._0;
  const _it = _M0MPC15array13ReadOnlyArray4iterGsE(_M0FP46f4ah6o3dsh7browser2sw20legacy__cache__names);
  while (true) {
    const _bind$3 = _M0MPB4Iter4nextGRP411moonbitlang5async8internal9coroutine9CoroutineE(_it);
    if (_bind$3 === undefined) {
      break;
    } else {
      const _Some = _bind$3;
      const _name = _Some;
      if (_M0MPC15array5Array8containsGsE(_cont_param, _name)) {
        return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(_name));
      }
      continue;
    }
  }
  return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(undefined));
}
function _M0FP46f4ah6o3dsh7browser2sw24find__legacy__generation(_cont, _err_cont) {
  const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(_M0FP46f4ah6o3dsh7browser2sw16sw__cache__names(), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param) => {
    let _err;
    _L: {
      const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw24find__legacy__generationN16_2aasync__driverS924(new _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2efind__legacy__generationL5State8State__0(_cont_param));
      let _tmp$2;
      if (_bind$4.$tag === 1) {
        const _ok = _bind$4;
        _tmp$2 = _ok._0;
      } else {
        const _err$2 = _bind$4;
        _err = _err$2._0;
        break _L;
      }
      const _tmp$3 = _tmp$2;
      if (_tmp$3.$tag === 1) {
        const _Some = _tmp$3;
        const _payload = _Some._0;
        _cont(_payload);
        return;
      } else {
        return;
      }
    }
    _err_cont(_err);
  }, _err_cont);
  let _tmp$2;
  if (_bind$3.$tag === 1) {
    const _ok = _bind$3;
    _tmp$2 = _ok._0;
  } else {
    return _bind$3;
  }
  const _tmp$3 = _tmp$2;
  if (_tmp$3.$tag === 1) {
    const _Some = _tmp$3;
    const _payload = _Some._0;
    return _M0FP46f4ah6o3dsh7browser2sw24find__legacy__generationN16_2aasync__driverS924(new _M0DTP46f4ah6o3dsh7browser2sw57_24f4ah6o_2fdsh_2fbrowser_2fsw_2efind__legacy__generationL5State8State__0(_payload));
  } else {
    return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
  }
}
function _M0FP46f4ah6o3dsh7browser2sw19window__client__idsN16_2aasync__driverS937(_state) {
  const _State_0 = _state;
  const _cont_param = _State_0._0;
  const ids = [];
  const _bind$3 = _cont_param.length;
  let _tmp$2 = 0;
  while (true) {
    const _ = _tmp$2;
    if (_ < _bind$3) {
      const client = _cont_param[_];
      _M0MPC15array5Array4pushGsE(ids, _M0FP46f4ah6o3dsh7browser2sw14sw__client__id(client));
      _tmp$2 = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return new _M0DTPC16result6ResultGORPB5ArrayGsERPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGRPB5ArrayGsEE4Some(ids));
}
function _M0FP46f4ah6o3dsh7browser2sw19window__client__ids(_cont, _err_cont) {
  const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(_M0FP46f4ah6o3dsh7browser2sw23sw__clients__match__all("window", true), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param) => {
    let _err;
    _L: {
      const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw19window__client__idsN16_2aasync__driverS937(new _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewindow__client__idsL5State8State__0(_cont_param));
      let _tmp$2;
      if (_bind$4.$tag === 1) {
        const _ok = _bind$4;
        _tmp$2 = _ok._0;
      } else {
        const _err$2 = _bind$4;
        _err = _err$2._0;
        break _L;
      }
      const _tmp$3 = _tmp$2;
      if (_tmp$3.$tag === 1) {
        const _Some = _tmp$3;
        const _payload = _Some._0;
        _cont(_payload);
        return;
      } else {
        return;
      }
    }
    _err_cont(_err);
  }, _err_cont);
  let _tmp$2;
  if (_bind$3.$tag === 1) {
    const _ok = _bind$3;
    _tmp$2 = _ok._0;
  } else {
    return _bind$3;
  }
  const _tmp$3 = _tmp$2;
  if (_tmp$3.$tag === 1) {
    const _Some = _tmp$3;
    const _payload = _Some._0;
    return _M0FP46f4ah6o3dsh7browser2sw19window__client__idsN16_2aasync__driverS937(new _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2ewindow__client__idsL5State8State__0(_payload));
  } else {
    return new _M0DTPC16result6ResultGORPB5ArrayGsERPC15error5ErrorE2Ok(_M0DTPC16option6OptionGRPB5ArrayGsEE4None__);
  }
}
function _M0FP46f4ah6o3dsh7browser2sw26clear__generation__staging(generation, _cont, _err_cont) {
  return _M0FP46f4ah6o3dsh7browser2sw16delete__metadata(_M0FP46f4ah6o3dsh7browser2sw22encoded__metadata__key(_M0FP46f4ah6o3dsh7browser2sw20sw__location__origin(), _M0FP46f4ah6o3dsh7browser2sw15staging__prefix, generation), _cont, _err_cont);
}
function _M0FP46f4ah6o3dsh7browser2sw19stage__for__installN16_2aasync__driverS954(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _State_0 = _state$2;
        const _err_cont = _State_0._3;
        const _cont = _State_0._2;
        const generation = _State_0._1;
        return _M0FP46f4ah6o3dsh7browser2sw26clear__generation__staging(generation, _cont, _err_cont);
      }
      case 1: {
        return new _M0DTPC16result6ResultGOuRPC15error5ErrorE3Err(new _M0DTPC15error5Error59f4ah6o_2fdsh_2fbrowser_2fsw_2eWorkerFailure_2eWorkerFailure("Unable to record the staged offline shell"));
      }
      case 2: {
        const _State_2 = _state$2;
        const _err_cont$2 = _State_2._3;
        const _cont$2 = _State_2._2;
        const generation$2 = _State_2._1;
        const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw26clear__generation__staging(generation$2, (_cont_param) => {
          let _err;
          _L$2: {
            const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw19stage__for__installN16_2aasync__driverS954(new _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__1(_cont_param));
            let _bind$5;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _bind$5 = _ok._0;
            } else {
              const _err$2 = _bind$4;
              _err = _err$2._0;
              break _L$2;
            }
            if (_bind$5 === -1) {
              return;
            } else {
              const _Some = _bind$5;
              const _payload = _Some;
              _cont$2(_payload);
              return;
            }
          }
          _err_cont$2(_err);
        }, _err_cont$2);
        let _bind$4;
        if (_bind$3.$tag === 1) {
          const _ok = _bind$3;
          _bind$4 = _ok._0;
        } else {
          return _bind$3;
        }
        if (_bind$4 === -1) {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        } else {
          const _Some = _bind$4;
          const _payload = _Some;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__1(_payload);
          continue _L;
        }
      }
      case 3: {
        const _State_3 = _state$2;
        const _err_cont$3 = _State_3._3;
        const _cont$3 = _State_3._2;
        const generation$3 = _State_3._1;
        const _cont_param = _State_3._0;
        if (!_cont_param) {
          const _bind$5 = _M0MP311moonbitlang5async9js__async7Promise4waitGbE(_M0FP46f4ah6o3dsh7browser2sw17sw__cache__delete(generation$3), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$2) => {
            let _err;
            _L$2: {
              const _bind$6 = _M0FP46f4ah6o3dsh7browser2sw19stage__for__installN16_2aasync__driverS954(new _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__2(_cont_param$2, generation$3, _cont$3, _err_cont$3));
              let _bind$7;
              if (_bind$6.$tag === 1) {
                const _ok = _bind$6;
                _bind$7 = _ok._0;
              } else {
                const _err$2 = _bind$6;
                _err = _err$2._0;
                break _L$2;
              }
              if (_bind$7 === -1) {
                return;
              } else {
                const _Some = _bind$7;
                const _payload = _Some;
                _cont$3(_payload);
                return;
              }
            }
            _err_cont$3(_err);
          }, _err_cont$3);
          let _bind$6;
          if (_bind$5.$tag === 1) {
            const _ok = _bind$5;
            _bind$6 = _ok._0;
          } else {
            return _bind$5;
          }
          if (_bind$6 === -1) {
            return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
          } else {
            const _Some = _bind$6;
            const _payload = _Some;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__2(_payload, generation$3, _cont$3, _err_cont$3);
            continue _L;
          }
        } else {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__0(undefined, generation$3, _cont$3, _err_cont$3);
          continue _L;
        }
      }
      default: {
        const _State_4 = _state$2;
        const _err_cont$4 = _State_4._2;
        const _cont$4 = _State_4._1;
        const _cont_param$2 = _State_4._0;
        if (_cont_param$2 === undefined) {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE3Err(new _M0DTPC15error5Error59f4ah6o_2fdsh_2fbrowser_2fsw_2eWorkerFailure_2eWorkerFailure("Unable to stage a complete offline shell"));
        } else {
          const _Some = _cont_param$2;
          const _generation = _Some;
          const _p = _M0FP46f4ah6o3dsh7browser2sw20sw__location__origin();
          const _bind$5 = _M0FP46f4ah6o3dsh7browser2sw15write__metadata(`${_p}${_M0FP46f4ah6o3dsh7browser2sw12pending__key}`, _generation, (_cont_param$3) => {
            let _err;
            _L$2: {
              const _bind$6 = _M0FP46f4ah6o3dsh7browser2sw19stage__for__installN16_2aasync__driverS954(new _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__3(_cont_param$3, _generation, _cont$4, _err_cont$4));
              let _bind$7;
              if (_bind$6.$tag === 1) {
                const _ok = _bind$6;
                _bind$7 = _ok._0;
              } else {
                const _err$2 = _bind$6;
                _err = _err$2._0;
                break _L$2;
              }
              if (_bind$7 === -1) {
                return;
              } else {
                const _Some$2 = _bind$7;
                const _payload = _Some$2;
                _cont$4(_payload);
                return;
              }
            }
            _err_cont$4(_err);
          }, _err_cont$4);
          let _bind$6;
          if (_bind$5.$tag === 1) {
            const _ok = _bind$5;
            _bind$6 = _ok._0;
          } else {
            return _bind$5;
          }
          if (_bind$6 === -1) {
            return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
          } else {
            const _Some$2 = _bind$6;
            const _payload = _Some$2;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__3(_payload, _generation, _cont$4, _err_cont$4);
            continue _L;
          }
        }
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw19stage__for__install(_cont, _err_cont) {
  const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw25create__shell__generation((_cont_param) => {
    let _err;
    _L: {
      const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw19stage__for__installN16_2aasync__driverS954(new _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__4(_cont_param, _cont, _err_cont));
      let _bind$5;
      if (_bind$4.$tag === 1) {
        const _ok = _bind$4;
        _bind$5 = _ok._0;
      } else {
        const _err$2 = _bind$4;
        _err = _err$2._0;
        break _L;
      }
      if (_bind$5 === -1) {
        return;
      } else {
        const _Some = _bind$5;
        const _payload = _Some;
        _cont(_payload);
        return;
      }
    }
    _err_cont(_err);
  }, _err_cont);
  let _tmp$2;
  if (_bind$3.$tag === 1) {
    const _ok = _bind$3;
    _tmp$2 = _ok._0;
  } else {
    return _bind$3;
  }
  const _tmp$3 = _tmp$2;
  if (_tmp$3.$tag === 1) {
    const _Some = _tmp$3;
    const _payload = _Some._0;
    return _M0FP46f4ah6o3dsh7browser2sw19stage__for__installN16_2aasync__driverS954(new _M0DTP46f4ah6o3dsh7browser2sw52_24f4ah6o_2fdsh_2fbrowser_2fsw_2estage__for__installL5State8State__4(_payload, _cont, _err_cont));
  } else {
    return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
  }
}
function _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generationsN16_2aasync__driverS1007(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _$42$for_0 = _state$2;
        const _err_cont = _$42$for_0._5;
        const _cont = _$42$for_0._4;
        const _bind$3 = _$42$for_0._3;
        const names = _$42$for_0._2;
        const retained = _$42$for_0._1;
        const _ = _$42$for_0._0;
        if (_ < _bind$3) {
          const name = names[_];
          if (_M0FP46f4ah6o3dsh7browser2sw20is__generation__name(name) && !_M0MPC15array5Array8containsGsE(retained, name)) {
            const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitGbE(_M0FP46f4ah6o3dsh7browser2sw17sw__cache__delete(name), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param) => {
              let _err;
              _L$2: {
                const _bind$5 = _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generationsN16_2aasync__driverS1007(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__2(_cont_param, retained, names, _, _bind$3, _cont, _err_cont));
                let _bind$6;
                if (_bind$5.$tag === 1) {
                  const _ok = _bind$5;
                  _bind$6 = _ok._0;
                } else {
                  const _err$2 = _bind$5;
                  _err = _err$2._0;
                  break _L$2;
                }
                if (_bind$6 === -1) {
                  return;
                } else {
                  const _Some = _bind$6;
                  const _payload = _Some;
                  _cont(_payload);
                  return;
                }
              }
              _err_cont(_err);
            }, _err_cont);
            let _bind$5;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _bind$5 = _ok._0;
            } else {
              return _bind$4;
            }
            if (_bind$5 === -1) {
              return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
            } else {
              const _Some = _bind$5;
              const _payload = _Some;
              _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__2(_payload, retained, names, _, _bind$3, _cont, _err_cont);
              continue _L;
            }
          } else {
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__1(undefined, retained, names, _, _bind$3, _cont, _err_cont);
            continue _L;
          }
        } else {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(undefined);
        }
      }
      case 1: {
        const _State_1 = _state$2;
        const _err_cont$2 = _State_1._6;
        const _cont$2 = _State_1._5;
        const _bind$4 = _State_1._4;
        const _$2 = _State_1._3;
        const names$2 = _State_1._2;
        const retained$2 = _State_1._1;
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9_2afor__0(_$2 + 1 | 0, retained$2, names$2, _bind$4, _cont$2, _err_cont$2);
        continue _L;
      }
      case 2: {
        const _State_2 = _state$2;
        const _err_cont$3 = _State_2._6;
        const _cont$3 = _State_2._5;
        const _bind$5 = _State_2._4;
        const _$3 = _State_2._3;
        const names$3 = _State_2._2;
        const retained$3 = _State_2._1;
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__1(undefined, retained$3, names$3, _$3, _bind$5, _cont$3, _err_cont$3);
        continue _L;
      }
      case 3: {
        const _State_3 = _state$2;
        const _err_cont$4 = _State_3._3;
        const _cont$4 = _State_3._2;
        const retained$4 = _State_3._1;
        const _cont_param = _State_3._0;
        const _bind$6 = _cont_param.length;
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9_2afor__0(0, retained$4, _cont_param, _bind$6, _cont$4, _err_cont$4);
        continue _L;
      }
      case 4: {
        const _State_4 = _state$2;
        const _err_cont$5 = _State_4._3;
        const _cont$5 = _State_4._2;
        const retained$5 = _State_4._1;
        const _bind$7 = _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(_M0FP46f4ah6o3dsh7browser2sw16sw__cache__names(), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$2) => {
          let _err;
          _L$2: {
            const _bind$8 = _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generationsN16_2aasync__driverS1007(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__3(_cont_param$2, retained$5, _cont$5, _err_cont$5));
            let _bind$9;
            if (_bind$8.$tag === 1) {
              const _ok = _bind$8;
              _bind$9 = _ok._0;
            } else {
              const _err$2 = _bind$8;
              _err = _err$2._0;
              break _L$2;
            }
            if (_bind$9 === -1) {
              return;
            } else {
              const _Some = _bind$9;
              const _payload = _Some;
              _cont$5(_payload);
              return;
            }
          }
          _err_cont$5(_err);
        }, _err_cont$5);
        let _tmp$3;
        if (_bind$7.$tag === 1) {
          const _ok = _bind$7;
          _tmp$3 = _ok._0;
        } else {
          return _bind$7;
        }
        const _tmp$4 = _tmp$3;
        if (_tmp$4.$tag === 1) {
          const _Some = _tmp$4;
          const _payload = _Some._0;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__3(_payload, retained$5, _cont$5, _err_cont$5);
          continue _L;
        } else {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        }
      }
      case 5: {
        const _$42$for_5 = _state$2;
        const _err_cont$6 = _$42$for_5._7;
        const _cont$6 = _$42$for_5._6;
        const _bind$8 = _$42$for_5._5;
        const metadata_keys = _$42$for_5._4;
        const retained$6 = _$42$for_5._3;
        const live_clients = _$42$for_5._2;
        const meta = _$42$for_5._1;
        const _$4 = _$42$for_5._0;
        if (_$4 < _bind$8) {
          const request = metadata_keys[_$4];
          const key = _M0FP46f4ah6o3dsh7browser2sw16sw__request__url(request);
          const path = _M0FP46f4ah6o3dsh7browser2sw13sw__url__path(key);
          if (_M0MPC16string6String11has__prefix(path, new _M0TPC16string10StringView(_M0FP46f4ah6o3dsh7browser2sw15staging__prefix, 0, _M0FP46f4ah6o3dsh7browser2sw15staging__prefix.length))) {
            const encoded = _M0MPC16string10StringView9to__owned(_M0MPC16string6String21clamped__view_2einner(path, _M0FP46f4ah6o3dsh7browser2sw15staging__prefix.length, undefined));
            const generation = _M0FP46f4ah6o3dsh7browser2sw21sw__decode__component(encoded);
            if (_M0FP46f4ah6o3dsh7browser2sw20is__generation__name(generation) && !_M0MPC15array5Array8containsGsE(retained$6, generation)) {
              _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__6(_M0MPC15array5Array4pushGsE(retained$6, generation), meta, live_clients, retained$6, metadata_keys, _$4, _bind$8, _cont$6, _err_cont$6);
              continue _L;
            } else {
              _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__6(undefined, meta, live_clients, retained$6, metadata_keys, _$4, _bind$8, _cont$6, _err_cont$6);
              continue _L;
            }
          } else {
            if (_M0MPC16string6String11has__prefix(path, new _M0TPC16string10StringView(_M0FP46f4ah6o3dsh7browser2sw19client__pin__prefix, 0, _M0FP46f4ah6o3dsh7browser2sw19client__pin__prefix.length))) {
              const encoded = _M0MPC16string10StringView9to__owned(_M0MPC16string6String21clamped__view_2einner(path, _M0FP46f4ah6o3dsh7browser2sw19client__pin__prefix.length, undefined));
              const client_id = _M0FP46f4ah6o3dsh7browser2sw21sw__decode__component(encoded);
              const _bind$9 = _M0MP311moonbitlang5async9js__async7Promise4waitGbE(_M0FP46f4ah6o3dsh7browser2sw14sw__cache__has(meta, key), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$2) => {
                let _err;
                _L$2: {
                  const _bind$10 = _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generationsN16_2aasync__driverS1007(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__11(_cont_param$2, meta, live_clients, retained$6, metadata_keys, key, client_id, _$4, _bind$8, _cont$6, _err_cont$6));
                  let _bind$11;
                  if (_bind$10.$tag === 1) {
                    const _ok = _bind$10;
                    _bind$11 = _ok._0;
                  } else {
                    const _err$2 = _bind$10;
                    _err = _err$2._0;
                    break _L$2;
                  }
                  if (_bind$11 === -1) {
                    return;
                  } else {
                    const _Some = _bind$11;
                    const _payload = _Some;
                    _cont$6(_payload);
                    return;
                  }
                }
                _err_cont$6(_err);
              }, _err_cont$6);
              let _bind$10;
              if (_bind$9.$tag === 1) {
                const _ok = _bind$9;
                _bind$10 = _ok._0;
              } else {
                return _bind$9;
              }
              if (_bind$10 === -1) {
                return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
              } else {
                const _Some = _bind$10;
                const _payload = _Some;
                _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__11(_payload, meta, live_clients, retained$6, metadata_keys, key, client_id, _$4, _bind$8, _cont$6, _err_cont$6);
                continue _L;
              }
            } else {
              _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__6(undefined, meta, live_clients, retained$6, metadata_keys, _$4, _bind$8, _cont$6, _err_cont$6);
              continue _L;
            }
          }
        } else {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__4(undefined, retained$6, _cont$6, _err_cont$6);
          continue _L;
        }
      }
      case 6: {
        const _State_6 = _state$2;
        const _err_cont$7 = _State_6._8;
        const _cont$7 = _State_6._7;
        const _bind$9 = _State_6._6;
        const _$5 = _State_6._5;
        const metadata_keys$2 = _State_6._4;
        const retained$7 = _State_6._3;
        const live_clients$2 = _State_6._2;
        const meta$2 = _State_6._1;
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9_2afor__5(_$5 + 1 | 0, meta$2, live_clients$2, retained$7, metadata_keys$2, _bind$9, _cont$7, _err_cont$7);
        continue _L;
      }
      case 7: {
        const _State_7 = _state$2;
        const _err_cont$8 = _State_7._8;
        const _cont$8 = _State_7._7;
        const _bind$10 = _State_7._6;
        const _$6 = _State_7._5;
        const metadata_keys$3 = _State_7._4;
        const retained$8 = _State_7._3;
        const live_clients$3 = _State_7._2;
        const meta$3 = _State_7._1;
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__6(undefined, meta$3, live_clients$3, retained$8, metadata_keys$3, _$6, _bind$10, _cont$8, _err_cont$8);
        continue _L;
      }
      case 8: {
        const _State_8 = _state$2;
        const _err_cont$9 = _State_8._10;
        const _cont$9 = _State_8._9;
        const _bind$11 = _State_8._8;
        const _$7 = _State_8._7;
        const client_id = _State_8._6;
        const key = _State_8._5;
        const metadata_keys$4 = _State_8._4;
        const retained$9 = _State_8._3;
        const live_clients$4 = _State_8._2;
        const meta$4 = _State_8._1;
        const _cont_param$2 = _State_8._0;
        if (!_M0MPC15array5Array8containsGsE(live_clients$4, client_id)) {
          const _bind$12 = _M0MP311moonbitlang5async9js__async7Promise4waitGbE(_M0FP46f4ah6o3dsh7browser2sw22sw__cache__delete__key(meta$4, key), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$3) => {
            let _err;
            _L$2: {
              const _bind$13 = _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generationsN16_2aasync__driverS1007(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__7(_cont_param$3, meta$4, live_clients$4, retained$9, metadata_keys$4, _$7, _bind$11, _cont$9, _err_cont$9));
              let _bind$14;
              if (_bind$13.$tag === 1) {
                const _ok = _bind$13;
                _bind$14 = _ok._0;
              } else {
                const _err$2 = _bind$13;
                _err = _err$2._0;
                break _L$2;
              }
              if (_bind$14 === -1) {
                return;
              } else {
                const _Some = _bind$14;
                const _payload = _Some;
                _cont$9(_payload);
                return;
              }
            }
            _err_cont$9(_err);
          }, _err_cont$9);
          let _bind$13;
          if (_bind$12.$tag === 1) {
            const _ok = _bind$12;
            _bind$13 = _ok._0;
          } else {
            return _bind$12;
          }
          if (_bind$13 === -1) {
            return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
          } else {
            const _Some = _bind$13;
            const _payload = _Some;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__7(_payload, meta$4, live_clients$4, retained$9, metadata_keys$4, _$7, _bind$11, _cont$9, _err_cont$9);
            continue _L;
          }
        } else {
          if (_cont_param$2 === undefined) {
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__6(undefined, meta$4, live_clients$4, retained$9, metadata_keys$4, _$7, _bind$11, _cont$9, _err_cont$9);
            continue _L;
          } else {
            const _Some = _cont_param$2;
            const _name = _Some;
            if (_M0FP46f4ah6o3dsh7browser2sw20is__generation__name(_name) && !_M0MPC15array5Array8containsGsE(retained$9, _name)) {
              _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__6(_M0MPC15array5Array4pushGsE(retained$9, _name), meta$4, live_clients$4, retained$9, metadata_keys$4, _$7, _bind$11, _cont$9, _err_cont$9);
              continue _L;
            } else {
              _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__6(undefined, meta$4, live_clients$4, retained$9, metadata_keys$4, _$7, _bind$11, _cont$9, _err_cont$9);
              continue _L;
            }
          }
        }
      }
      case 9: {
        const _State_9 = _state$2;
        const _err_cont$10 = _State_9._10;
        const _cont$10 = _State_9._9;
        const _bind$12 = _State_9._8;
        const _$8 = _State_9._7;
        const client_id$2 = _State_9._6;
        const key$2 = _State_9._5;
        const metadata_keys$5 = _State_9._4;
        const retained$10 = _State_9._3;
        const live_clients$5 = _State_9._2;
        const meta$5 = _State_9._1;
        const _cont_param$3 = _State_9._0;
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__8(_cont_param$3, meta$5, live_clients$5, retained$10, metadata_keys$5, key$2, client_id$2, _$8, _bind$12, _cont$10, _err_cont$10);
        continue _L;
      }
      case 10: {
        const _State_10 = _state$2;
        const _err_cont$11 = _State_10._10;
        const _cont$11 = _State_10._9;
        const _bind$13 = _State_10._8;
        const _$9 = _State_10._7;
        const client_id$3 = _State_10._6;
        const key$3 = _State_10._5;
        const metadata_keys$6 = _State_10._4;
        const retained$11 = _State_10._3;
        const live_clients$6 = _State_10._2;
        const meta$6 = _State_10._1;
        const _cont_param$4 = _State_10._0;
        const _bind$14 = _M0MP311moonbitlang5async9js__async7Promise4waitGsE(_M0FP46f4ah6o3dsh7browser2sw18sw__response__text(_cont_param$4), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$5) => {
          let _err;
          _L$2: {
            const _bind$15 = _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generationsN16_2aasync__driverS1007(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__9(_cont_param$5, meta$6, live_clients$6, retained$11, metadata_keys$6, key$3, client_id$3, _$9, _bind$13, _cont$11, _err_cont$11));
            let _bind$16;
            if (_bind$15.$tag === 1) {
              const _ok = _bind$15;
              _bind$16 = _ok._0;
            } else {
              const _err$2 = _bind$15;
              _err = _err$2._0;
              break _L$2;
            }
            if (_bind$16 === -1) {
              return;
            } else {
              const _Some = _bind$16;
              const _payload = _Some;
              _cont$11(_payload);
              return;
            }
          }
          _err_cont$11(_err);
        }, _err_cont$11);
        let _bind$15;
        if (_bind$14.$tag === 1) {
          const _ok = _bind$14;
          _bind$15 = _ok._0;
        } else {
          return _bind$14;
        }
        if (_bind$15 === undefined) {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        } else {
          const _Some = _bind$15;
          const _payload = _Some;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__9(_payload, meta$6, live_clients$6, retained$11, metadata_keys$6, key$3, client_id$3, _$9, _bind$13, _cont$11, _err_cont$11);
          continue _L;
        }
      }
      case 11: {
        const _State_11 = _state$2;
        const _err_cont$12 = _State_11._10;
        const _cont$12 = _State_11._9;
        const _bind$16 = _State_11._8;
        const _$10 = _State_11._7;
        const client_id$4 = _State_11._6;
        const key$4 = _State_11._5;
        const metadata_keys$7 = _State_11._4;
        const retained$12 = _State_11._3;
        const live_clients$7 = _State_11._2;
        const meta$7 = _State_11._1;
        const _cont_param$5 = _State_11._0;
        if (_cont_param$5) {
          const _bind$17 = _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(_M0FP46f4ah6o3dsh7browser2sw16sw__cache__match(meta$7, key$4), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$6) => {
            let _err;
            _L$2: {
              const _bind$18 = _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generationsN16_2aasync__driverS1007(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__10(_cont_param$6, meta$7, live_clients$7, retained$12, metadata_keys$7, key$4, client_id$4, _$10, _bind$16, _cont$12, _err_cont$12));
              let _bind$19;
              if (_bind$18.$tag === 1) {
                const _ok = _bind$18;
                _bind$19 = _ok._0;
              } else {
                const _err$2 = _bind$18;
                _err = _err$2._0;
                break _L$2;
              }
              if (_bind$19 === -1) {
                return;
              } else {
                const _Some = _bind$19;
                const _payload = _Some;
                _cont$12(_payload);
                return;
              }
            }
            _err_cont$12(_err);
          }, _err_cont$12);
          let _tmp$5;
          if (_bind$17.$tag === 1) {
            const _ok = _bind$17;
            _tmp$5 = _ok._0;
          } else {
            return _bind$17;
          }
          const _tmp$6 = _tmp$5;
          if (_tmp$6.$tag === 1) {
            const _Some = _tmp$6;
            const _payload = _Some._0;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__10(_payload, meta$7, live_clients$7, retained$12, metadata_keys$7, key$4, client_id$4, _$10, _bind$16, _cont$12, _err_cont$12);
            continue _L;
          } else {
            return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
          }
        } else {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State8State__8(undefined, meta$7, live_clients$7, retained$12, metadata_keys$7, key$4, client_id$4, _$10, _bind$16, _cont$12, _err_cont$12);
          continue _L;
        }
      }
      case 12: {
        const _State_12 = _state$2;
        const _err_cont$13 = _State_12._5;
        const _cont$13 = _State_12._4;
        const retained$13 = _State_12._3;
        const live_clients$8 = _State_12._2;
        const meta$8 = _State_12._1;
        const _cont_param$6 = _State_12._0;
        const _bind$17 = _cont_param$6.length;
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9_2afor__5(0, meta$8, live_clients$8, retained$13, _cont_param$6, _bind$17, _cont$13, _err_cont$13);
        continue _L;
      }
      case 13: {
        const _State_13 = _state$2;
        const _err_cont$14 = _State_13._5;
        const _cont$14 = _State_13._4;
        const retained$14 = _State_13._3;
        const live_clients$9 = _State_13._2;
        const meta$9 = _State_13._1;
        const _cont_param$7 = _State_13._0;
        if (_cont_param$7 === undefined) {
        } else {
          const _Some = _cont_param$7;
          const _pending = _Some;
          if (_M0FP46f4ah6o3dsh7browser2sw20is__generation__name(_pending)) {
            _M0MPC15array5Array4pushGsE(retained$14, _pending);
          }
        }
        const _bind$18 = _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(_M0FP46f4ah6o3dsh7browser2sw15sw__cache__keys(meta$9), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$8) => {
          let _err;
          _L$2: {
            const _bind$19 = _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generationsN16_2aasync__driverS1007(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__12(_cont_param$8, meta$9, live_clients$9, retained$14, _cont$14, _err_cont$14));
            let _bind$20;
            if (_bind$19.$tag === 1) {
              const _ok = _bind$19;
              _bind$20 = _ok._0;
            } else {
              const _err$2 = _bind$19;
              _err = _err$2._0;
              break _L$2;
            }
            if (_bind$20 === -1) {
              return;
            } else {
              const _Some = _bind$20;
              const _payload = _Some;
              _cont$14(_payload);
              return;
            }
          }
          _err_cont$14(_err);
        }, _err_cont$14);
        let _tmp$5;
        if (_bind$18.$tag === 1) {
          const _ok = _bind$18;
          _tmp$5 = _ok._0;
        } else {
          return _bind$18;
        }
        const _tmp$6 = _tmp$5;
        if (_tmp$6.$tag === 1) {
          const _Some = _tmp$6;
          const _payload = _Some._0;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__12(_payload, meta$9, live_clients$9, retained$14, _cont$14, _err_cont$14);
          continue _L;
        } else {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        }
      }
      case 14: {
        const _State_14 = _state$2;
        const _err_cont$15 = _State_14._6;
        const _cont$15 = _State_14._5;
        const retained$15 = _State_14._4;
        const live_clients$10 = _State_14._3;
        const meta$10 = _State_14._2;
        const origin = _State_14._1;
        const _cont_param$8 = _State_14._0;
        if (_cont_param$8 === undefined) {
        } else {
          const _Some = _cont_param$8;
          const _active = _Some;
          _M0MPC15array5Array4pushGsE(retained$15, _active);
        }
        const _bind$19 = _M0FP46f4ah6o3dsh7browser2sw14read__metadata(`${origin}${_M0FP46f4ah6o3dsh7browser2sw12pending__key}`, (_cont_param$9) => {
          let _err;
          _L$2: {
            const _bind$20 = _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generationsN16_2aasync__driverS1007(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__13(_cont_param$9, meta$10, live_clients$10, retained$15, _cont$15, _err_cont$15));
            let _bind$21;
            if (_bind$20.$tag === 1) {
              const _ok = _bind$20;
              _bind$21 = _ok._0;
            } else {
              const _err$2 = _bind$20;
              _err = _err$2._0;
              break _L$2;
            }
            if (_bind$21 === -1) {
              return;
            } else {
              const _Some = _bind$21;
              const _payload = _Some;
              _cont$15(_payload);
              return;
            }
          }
          _err_cont$15(_err);
        }, _err_cont$15);
        let _tmp$7;
        if (_bind$19.$tag === 1) {
          const _ok = _bind$19;
          _tmp$7 = _ok._0;
        } else {
          return _bind$19;
        }
        const _tmp$8 = _tmp$7;
        if (_tmp$8.$tag === 1) {
          const _Some = _tmp$8;
          const _payload = _Some._0;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__13(_payload, meta$10, live_clients$10, retained$15, _cont$15, _err_cont$15);
          continue _L;
        } else {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        }
      }
      case 15: {
        const _State_15 = _state$2;
        const _err_cont$16 = _State_15._5;
        const _cont$16 = _State_15._4;
        const meta$11 = _State_15._3;
        const origin$2 = _State_15._2;
        const additional_live_clients = _State_15._1;
        const _cont_param$9 = _State_15._0;
        const _bind$20 = additional_live_clients.length;
        let _tmp$9 = 0;
        while (true) {
          const _$11 = _tmp$9;
          if (_$11 < _bind$20) {
            const client_id$5 = additional_live_clients[_$11];
            if (!_M0MPC15array5Array8containsGsE(_cont_param$9, client_id$5)) {
              _M0MPC15array5Array4pushGsE(_cont_param$9, client_id$5);
            }
            _tmp$9 = _$11 + 1 | 0;
            continue;
          } else {
            break;
          }
        }
        const retained$16 = [];
        const _bind$21 = _M0FP46f4ah6o3dsh7browser2sw24read__active__generation((_cont_param$10) => {
          let _err;
          _L$2: {
            const _bind$22 = _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generationsN16_2aasync__driverS1007(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__14(_cont_param$10, origin$2, meta$11, _cont_param$9, retained$16, _cont$16, _err_cont$16));
            let _bind$23;
            if (_bind$22.$tag === 1) {
              const _ok = _bind$22;
              _bind$23 = _ok._0;
            } else {
              const _err$2 = _bind$22;
              _err = _err$2._0;
              break _L$2;
            }
            if (_bind$23 === -1) {
              return;
            } else {
              const _Some = _bind$23;
              const _payload = _Some;
              _cont$16(_payload);
              return;
            }
          }
          _err_cont$16(_err);
        }, _err_cont$16);
        let _tmp$10;
        if (_bind$21.$tag === 1) {
          const _ok = _bind$21;
          _tmp$10 = _ok._0;
        } else {
          return _bind$21;
        }
        const _tmp$11 = _tmp$10;
        if (_tmp$11.$tag === 1) {
          const _Some = _tmp$11;
          const _payload = _Some._0;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__14(_payload, origin$2, meta$11, _cont_param$9, retained$16, _cont$16, _err_cont$16);
          continue _L;
        } else {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        }
      }
      default: {
        const _State_16 = _state$2;
        const _err_cont$17 = _State_16._4;
        const _cont$17 = _State_16._3;
        const origin$3 = _State_16._2;
        const additional_live_clients$2 = _State_16._1;
        const _cont_param$10 = _State_16._0;
        const _bind$22 = _M0FP46f4ah6o3dsh7browser2sw19window__client__ids((_cont_param$11) => {
          let _err;
          _L$2: {
            const _bind$23 = _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generationsN16_2aasync__driverS1007(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__15(_cont_param$11, additional_live_clients$2, origin$3, _cont_param$10, _cont$17, _err_cont$17));
            let _bind$24;
            if (_bind$23.$tag === 1) {
              const _ok = _bind$23;
              _bind$24 = _ok._0;
            } else {
              const _err$2 = _bind$23;
              _err = _err$2._0;
              break _L$2;
            }
            if (_bind$24 === -1) {
              return;
            } else {
              const _Some = _bind$24;
              const _payload = _Some;
              _cont$17(_payload);
              return;
            }
          }
          _err_cont$17(_err);
        }, _err_cont$17);
        let _tmp$12;
        if (_bind$22.$tag === 1) {
          const _ok = _bind$22;
          _tmp$12 = _ok._0;
        } else {
          return _bind$22;
        }
        const _tmp$13 = _tmp$12;
        if (_tmp$13.$tag === 1) {
          const _Some = _tmp$13;
          const _payload = _Some._0;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__15(_payload, additional_live_clients$2, origin$3, _cont_param$10, _cont$17, _err_cont$17);
          continue _L;
        } else {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        }
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generations(additional_live_clients, _cont, _err_cont) {
  const origin = _M0FP46f4ah6o3dsh7browser2sw20sw__location__origin();
  const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw15metadata__cache((_cont_param) => {
    let _err;
    _L: {
      const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generationsN16_2aasync__driverS1007(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__16(_cont_param, additional_live_clients, origin, _cont, _err_cont));
      let _bind$5;
      if (_bind$4.$tag === 1) {
        const _ok = _bind$4;
        _bind$5 = _ok._0;
      } else {
        const _err$2 = _bind$4;
        _err = _err$2._0;
        break _L;
      }
      if (_bind$5 === -1) {
        return;
      } else {
        const _Some = _bind$5;
        const _payload = _Some;
        _cont(_payload);
        return;
      }
    }
    _err_cont(_err);
  }, _err_cont);
  let _tmp$2;
  if (_bind$3.$tag === 1) {
    const _ok = _bind$3;
    _tmp$2 = _ok._0;
  } else {
    return _bind$3;
  }
  const _tmp$3 = _tmp$2;
  if (_tmp$3.$tag === 1) {
    const _Some = _tmp$3;
    const _payload = _Some._0;
    return _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generationsN16_2aasync__driverS1007(new _M0DTP46f4ah6o3dsh7browser2sw58_24f4ah6o_2fdsh_2fbrowser_2fsw_2ecleanup__old__generationsL5State9State__16(_payload, additional_live_clients, origin, _cont, _err_cont));
  } else {
    return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
  }
}
function _M0FP46f4ah6o3dsh7browser2sw20activate__generationN16_2aasync__driverS1231(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _State_0 = _state$2;
        const _err_cont = _State_0._3;
        const _cont = _State_0._2;
        const clients_before_claim = _State_0._1;
        return _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generations(clients_before_claim, _cont, _err_cont);
      }
      case 1: {
        const _State_1 = _state$2;
        const _err_cont$2 = _State_1._3;
        const _cont$2 = _State_1._2;
        const clients_before_claim$2 = _State_1._1;
        const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGuE(_M0FP46f4ah6o3dsh7browser2sw18sw__clients__claim(), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param) => {
          let _err;
          _L$2: {
            const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw20activate__generationN16_2aasync__driverS1231(new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__0(_cont_param, clients_before_claim$2, _cont$2, _err_cont$2));
            let _bind$5;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _bind$5 = _ok._0;
            } else {
              const _err$2 = _bind$4;
              _err = _err$2._0;
              break _L$2;
            }
            if (_bind$5 === -1) {
              return;
            } else {
              const _Some = _bind$5;
              const _payload = _Some;
              _cont$2(_payload);
              return;
            }
          }
          _err_cont$2(_err);
        }, _err_cont$2);
        let _bind$4;
        if (_bind$3.$tag === 1) {
          const _ok = _bind$3;
          _bind$4 = _ok._0;
        } else {
          return _bind$3;
        }
        if (_bind$4 === -1) {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        } else {
          const _Some = _bind$4;
          const _payload = _Some;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__0(_payload, clients_before_claim$2, _cont$2, _err_cont$2);
          continue _L;
        }
      }
      case 2: {
        const _State_2 = _state$2;
        const _err_cont$3 = _State_2._4;
        const _cont$3 = _State_2._3;
        const clients_before_claim$3 = _State_2._2;
        const origin = _State_2._1;
        const _bind$5 = _M0FP46f4ah6o3dsh7browser2sw16delete__metadata(`${origin}${_M0FP46f4ah6o3dsh7browser2sw12pending__key}`, (_cont_param) => {
          let _err;
          _L$2: {
            const _bind$6 = _M0FP46f4ah6o3dsh7browser2sw20activate__generationN16_2aasync__driverS1231(new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__1(_cont_param, clients_before_claim$3, _cont$3, _err_cont$3));
            let _bind$7;
            if (_bind$6.$tag === 1) {
              const _ok = _bind$6;
              _bind$7 = _ok._0;
            } else {
              const _err$2 = _bind$6;
              _err = _err$2._0;
              break _L$2;
            }
            if (_bind$7 === -1) {
              return;
            } else {
              const _Some = _bind$7;
              const _payload = _Some;
              _cont$3(_payload);
              return;
            }
          }
          _err_cont$3(_err);
        }, _err_cont$3);
        let _bind$6;
        if (_bind$5.$tag === 1) {
          const _ok = _bind$5;
          _bind$6 = _ok._0;
        } else {
          return _bind$5;
        }
        if (_bind$6 === -1) {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        } else {
          const _Some = _bind$6;
          const _payload = _Some;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__1(_payload, clients_before_claim$3, _cont$3, _err_cont$3);
          continue _L;
        }
      }
      case 3: {
        const _State_3 = _state$2;
        const _err_cont$4 = _State_3._4;
        const _cont$4 = _State_3._3;
        const clients_before_claim$4 = _State_3._2;
        const origin$2 = _State_3._1;
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__2(undefined, origin$2, clients_before_claim$4, _cont$4, _err_cont$4);
        continue _L;
      }
      case 4: {
        const _State_4 = _state$2;
        const _err_cont$5 = _State_4._6;
        const _cont$5 = _State_4._5;
        const clients_before_claim$5 = _State_4._4;
        const current = _State_4._3;
        const pending = _State_4._2;
        const origin$3 = _State_4._1;
        let active;
        if (pending === undefined) {
          active = current;
        } else {
          const _Some = pending;
          const _name = _Some;
          active = _name;
        }
        if (active === undefined) {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__2(undefined, origin$3, clients_before_claim$5, _cont$5, _err_cont$5);
          continue _L;
        } else {
          const _Some = active;
          const _name = _Some;
          const _bind$7 = _M0FP46f4ah6o3dsh7browser2sw15write__metadata(`${origin$3}${_M0FP46f4ah6o3dsh7browser2sw11active__key}`, _name, (_cont_param) => {
            let _err;
            _L$2: {
              const _bind$8 = _M0FP46f4ah6o3dsh7browser2sw20activate__generationN16_2aasync__driverS1231(new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__3(_cont_param, origin$3, clients_before_claim$5, _cont$5, _err_cont$5));
              let _bind$9;
              if (_bind$8.$tag === 1) {
                const _ok = _bind$8;
                _bind$9 = _ok._0;
              } else {
                const _err$2 = _bind$8;
                _err = _err$2._0;
                break _L$2;
              }
              if (_bind$9 === -1) {
                return;
              } else {
                const _Some$2 = _bind$9;
                const _payload = _Some$2;
                _cont$5(_payload);
                return;
              }
            }
            _err_cont$5(_err);
          }, _err_cont$5);
          let _bind$8;
          if (_bind$7.$tag === 1) {
            const _ok = _bind$7;
            _bind$8 = _ok._0;
          } else {
            return _bind$7;
          }
          if (_bind$8 === -1) {
            return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
          } else {
            const _Some$2 = _bind$8;
            const _payload = _Some$2;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__3(_payload, origin$3, clients_before_claim$5, _cont$5, _err_cont$5);
            continue _L;
          }
        }
      }
      case 5: {
        const _$42$for_5 = _state$2;
        const _err_cont$6 = _$42$for_5._8;
        const _cont$6 = _$42$for_5._7;
        const _bind$7 = _$42$for_5._6;
        const generation = _$42$for_5._5;
        const clients_before_claim$6 = _$42$for_5._4;
        const current$2 = _$42$for_5._3;
        const pending$2 = _$42$for_5._2;
        const origin$4 = _$42$for_5._1;
        const _ = _$42$for_5._0;
        if (_ < _bind$7) {
          const client_id = clients_before_claim$6[_];
          const _bind$8 = _M0FP46f4ah6o3dsh7browser2sw24read__client__generation(client_id, (_cont_param) => {
            let _err;
            _L$2: {
              const _bind$9 = _M0FP46f4ah6o3dsh7browser2sw20activate__generationN16_2aasync__driverS1231(new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__8(_cont_param, origin$4, pending$2, current$2, clients_before_claim$6, generation, client_id, _, _bind$7, _cont$6, _err_cont$6));
              let _bind$10;
              if (_bind$9.$tag === 1) {
                const _ok = _bind$9;
                _bind$10 = _ok._0;
              } else {
                const _err$2 = _bind$9;
                _err = _err$2._0;
                break _L$2;
              }
              if (_bind$10 === -1) {
                return;
              } else {
                const _Some = _bind$10;
                const _payload = _Some;
                _cont$6(_payload);
                return;
              }
            }
            _err_cont$6(_err);
          }, _err_cont$6);
          let _tmp$3;
          if (_bind$8.$tag === 1) {
            const _ok = _bind$8;
            _tmp$3 = _ok._0;
          } else {
            return _bind$8;
          }
          const _tmp$4 = _tmp$3;
          if (_tmp$4.$tag === 1) {
            const _Some = _tmp$4;
            const _payload = _Some._0;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__8(_payload, origin$4, pending$2, current$2, clients_before_claim$6, generation, client_id, _, _bind$7, _cont$6, _err_cont$6);
            continue _L;
          } else {
            return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
          }
        } else {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__4(undefined, origin$4, pending$2, current$2, clients_before_claim$6, _cont$6, _err_cont$6);
          continue _L;
        }
      }
      case 6: {
        const _State_6 = _state$2;
        const _err_cont$7 = _State_6._9;
        const _cont$7 = _State_6._8;
        const _bind$8 = _State_6._7;
        const _$2 = _State_6._6;
        const generation$2 = _State_6._5;
        const clients_before_claim$7 = _State_6._4;
        const current$3 = _State_6._3;
        const pending$3 = _State_6._2;
        const origin$5 = _State_6._1;
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9_2afor__5(_$2 + 1 | 0, origin$5, pending$3, current$3, clients_before_claim$7, generation$2, _bind$8, _cont$7, _err_cont$7);
        continue _L;
      }
      case 7: {
        const _State_7 = _state$2;
        const _err_cont$8 = _State_7._9;
        const _cont$8 = _State_7._8;
        const _bind$9 = _State_7._7;
        const _$3 = _State_7._6;
        const generation$3 = _State_7._5;
        const clients_before_claim$8 = _State_7._4;
        const current$4 = _State_7._3;
        const pending$4 = _State_7._2;
        const origin$6 = _State_7._1;
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__6(undefined, origin$6, pending$4, current$4, clients_before_claim$8, generation$3, _$3, _bind$9, _cont$8, _err_cont$8);
        continue _L;
      }
      case 8: {
        const _State_8 = _state$2;
        const _err_cont$9 = _State_8._10;
        const _cont$9 = _State_8._9;
        const _bind$10 = _State_8._8;
        const _$4 = _State_8._7;
        const client_id = _State_8._6;
        const generation$4 = _State_8._5;
        const clients_before_claim$9 = _State_8._4;
        const current$5 = _State_8._3;
        const pending$5 = _State_8._2;
        const origin$7 = _State_8._1;
        const _cont_param = _State_8._0;
        if (_cont_param === undefined) {
          const _bind$11 = _M0FP46f4ah6o3dsh7browser2sw15write__metadata(_M0FP46f4ah6o3dsh7browser2sw22encoded__metadata__key(origin$7, _M0FP46f4ah6o3dsh7browser2sw19client__pin__prefix, client_id), generation$4, (_cont_param$2) => {
            let _err;
            _L$2: {
              const _bind$12 = _M0FP46f4ah6o3dsh7browser2sw20activate__generationN16_2aasync__driverS1231(new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__7(_cont_param$2, origin$7, pending$5, current$5, clients_before_claim$9, generation$4, _$4, _bind$10, _cont$9, _err_cont$9));
              let _bind$13;
              if (_bind$12.$tag === 1) {
                const _ok = _bind$12;
                _bind$13 = _ok._0;
              } else {
                const _err$2 = _bind$12;
                _err = _err$2._0;
                break _L$2;
              }
              if (_bind$13 === -1) {
                return;
              } else {
                const _Some = _bind$13;
                const _payload = _Some;
                _cont$9(_payload);
                return;
              }
            }
            _err_cont$9(_err);
          }, _err_cont$9);
          let _bind$12;
          if (_bind$11.$tag === 1) {
            const _ok = _bind$11;
            _bind$12 = _ok._0;
          } else {
            return _bind$11;
          }
          if (_bind$12 === -1) {
            return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
          } else {
            const _Some = _bind$12;
            const _payload = _Some;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__7(_payload, origin$7, pending$5, current$5, clients_before_claim$9, generation$4, _$4, _bind$10, _cont$9, _err_cont$9);
            continue _L;
          }
        } else {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__6(undefined, origin$7, pending$5, current$5, clients_before_claim$9, generation$4, _$4, _bind$10, _cont$9, _err_cont$9);
          continue _L;
        }
      }
      case 9: {
        const _State_9 = _state$2;
        const _err_cont$10 = _State_9._5;
        const _cont$10 = _State_9._4;
        const current$6 = _State_9._3;
        const pending$6 = _State_9._2;
        const origin$8 = _State_9._1;
        const _cont_param$2 = _State_9._0;
        if (current$6 === undefined) {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__4(undefined, origin$8, pending$6, current$6, _cont_param$2, _cont$10, _err_cont$10);
          continue _L;
        } else {
          const _Some = current$6;
          const _generation = _Some;
          const _bind$11 = _cont_param$2.length;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9_2afor__5(0, origin$8, pending$6, current$6, _cont_param$2, _generation, _bind$11, _cont$10, _err_cont$10);
          continue _L;
        }
      }
      case 10: {
        const _State_10 = _state$2;
        const _err_cont$11 = _State_10._4;
        const _cont$11 = _State_10._3;
        const pending$7 = _State_10._2;
        const origin$9 = _State_10._1;
        const _cont_param$3 = _State_10._0;
        const _bind$11 = _M0FP46f4ah6o3dsh7browser2sw19window__client__ids((_cont_param$4) => {
          let _err;
          _L$2: {
            const _bind$12 = _M0FP46f4ah6o3dsh7browser2sw20activate__generationN16_2aasync__driverS1231(new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__9(_cont_param$4, origin$9, pending$7, _cont_param$3, _cont$11, _err_cont$11));
            let _bind$13;
            if (_bind$12.$tag === 1) {
              const _ok = _bind$12;
              _bind$13 = _ok._0;
            } else {
              const _err$2 = _bind$12;
              _err = _err$2._0;
              break _L$2;
            }
            if (_bind$13 === -1) {
              return;
            } else {
              const _Some = _bind$13;
              const _payload = _Some;
              _cont$11(_payload);
              return;
            }
          }
          _err_cont$11(_err);
        }, _err_cont$11);
        let _tmp$3;
        if (_bind$11.$tag === 1) {
          const _ok = _bind$11;
          _tmp$3 = _ok._0;
        } else {
          return _bind$11;
        }
        const _tmp$4 = _tmp$3;
        if (_tmp$4.$tag === 1) {
          const _Some = _tmp$4;
          const _payload = _Some._0;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State8State__9(_payload, origin$9, pending$7, _cont_param$3, _cont$11, _err_cont$11);
          continue _L;
        } else {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        }
      }
      case 11: {
        const _State_11 = _state$2;
        const _err_cont$12 = _State_11._4;
        const _cont$12 = _State_11._3;
        const pending$8 = _State_11._2;
        const origin$10 = _State_11._1;
        const _cont_param$4 = _State_11._0;
        if (_cont_param$4 === undefined) {
          const _bind$12 = _M0FP46f4ah6o3dsh7browser2sw24find__legacy__generation((_cont_param$5) => {
            let _err;
            _L$2: {
              const _bind$13 = _M0FP46f4ah6o3dsh7browser2sw20activate__generationN16_2aasync__driverS1231(new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__10(_cont_param$5, origin$10, pending$8, _cont$12, _err_cont$12));
              let _bind$14;
              if (_bind$13.$tag === 1) {
                const _ok = _bind$13;
                _bind$14 = _ok._0;
              } else {
                const _err$2 = _bind$13;
                _err = _err$2._0;
                break _L$2;
              }
              if (_bind$14 === -1) {
                return;
              } else {
                const _Some = _bind$14;
                const _payload = _Some;
                _cont$12(_payload);
                return;
              }
            }
            _err_cont$12(_err);
          }, _err_cont$12);
          let _tmp$5;
          if (_bind$12.$tag === 1) {
            const _ok = _bind$12;
            _tmp$5 = _ok._0;
          } else {
            return _bind$12;
          }
          const _tmp$6 = _tmp$5;
          if (_tmp$6.$tag === 1) {
            const _Some = _tmp$6;
            const _payload = _Some._0;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__10(_payload, origin$10, pending$8, _cont$12, _err_cont$12);
            continue _L;
          } else {
            return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
          }
        } else {
          const _Some = _cont_param$4;
          const _name = _Some;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__10(_name, origin$10, pending$8, _cont$12, _err_cont$12);
          continue _L;
        }
      }
      case 12: {
        const _State_12 = _state$2;
        const _err_cont$13 = _State_12._4;
        const _cont$13 = _State_12._3;
        const pending_name = _State_12._2;
        const origin$11 = _State_12._1;
        const _cont_param$5 = _State_12._0;
        let pending$9;
        _L$2: {
          _L$3: {
            if (pending_name === undefined) {
              break _L$3;
            } else {
              const _Some = pending_name;
              const _name = _Some;
              if (_M0FP46f4ah6o3dsh7browser2sw20is__generation__name(_name) && _M0MPC15array5Array8containsGsE(_cont_param$5, _name)) {
                pending$9 = _name;
              } else {
                break _L$3;
              }
            }
            break _L$2;
          }
          pending$9 = undefined;
        }
        const _bind$12 = _M0FP46f4ah6o3dsh7browser2sw24read__active__generation((_cont_param$6) => {
          let _err;
          _L$3: {
            const _bind$13 = _M0FP46f4ah6o3dsh7browser2sw20activate__generationN16_2aasync__driverS1231(new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__11(_cont_param$6, origin$11, pending$9, _cont$13, _err_cont$13));
            let _bind$14;
            if (_bind$13.$tag === 1) {
              const _ok = _bind$13;
              _bind$14 = _ok._0;
            } else {
              const _err$2 = _bind$13;
              _err = _err$2._0;
              break _L$3;
            }
            if (_bind$14 === -1) {
              return;
            } else {
              const _Some = _bind$14;
              const _payload = _Some;
              _cont$13(_payload);
              return;
            }
          }
          _err_cont$13(_err);
        }, _err_cont$13);
        let _tmp$5;
        if (_bind$12.$tag === 1) {
          const _ok = _bind$12;
          _tmp$5 = _ok._0;
        } else {
          return _bind$12;
        }
        const _tmp$6 = _tmp$5;
        if (_tmp$6.$tag === 1) {
          const _Some = _tmp$6;
          const _payload = _Some._0;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__11(_payload, origin$11, pending$9, _cont$13, _err_cont$13);
          continue _L;
        } else {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        }
      }
      default: {
        const _State_13 = _state$2;
        const _err_cont$14 = _State_13._3;
        const _cont$14 = _State_13._2;
        const origin$12 = _State_13._1;
        const _cont_param$6 = _State_13._0;
        const _bind$13 = _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(_M0FP46f4ah6o3dsh7browser2sw16sw__cache__names(), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$7) => {
          let _err;
          _L$3: {
            const _bind$14 = _M0FP46f4ah6o3dsh7browser2sw20activate__generationN16_2aasync__driverS1231(new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__12(_cont_param$7, origin$12, _cont_param$6, _cont$14, _err_cont$14));
            let _bind$15;
            if (_bind$14.$tag === 1) {
              const _ok = _bind$14;
              _bind$15 = _ok._0;
            } else {
              const _err$2 = _bind$14;
              _err = _err$2._0;
              break _L$3;
            }
            if (_bind$15 === -1) {
              return;
            } else {
              const _Some = _bind$15;
              const _payload = _Some;
              _cont$14(_payload);
              return;
            }
          }
          _err_cont$14(_err);
        }, _err_cont$14);
        let _tmp$7;
        if (_bind$13.$tag === 1) {
          const _ok = _bind$13;
          _tmp$7 = _ok._0;
        } else {
          return _bind$13;
        }
        const _tmp$8 = _tmp$7;
        if (_tmp$8.$tag === 1) {
          const _Some = _tmp$8;
          const _payload = _Some._0;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__12(_payload, origin$12, _cont_param$6, _cont$14, _err_cont$14);
          continue _L;
        } else {
          return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
        }
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw20activate__generation(_cont, _err_cont) {
  const origin = _M0FP46f4ah6o3dsh7browser2sw20sw__location__origin();
  const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw14read__metadata(`${origin}${_M0FP46f4ah6o3dsh7browser2sw12pending__key}`, (_cont_param) => {
    let _err;
    _L: {
      const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw20activate__generationN16_2aasync__driverS1231(new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__13(_cont_param, origin, _cont, _err_cont));
      let _bind$5;
      if (_bind$4.$tag === 1) {
        const _ok = _bind$4;
        _bind$5 = _ok._0;
      } else {
        const _err$2 = _bind$4;
        _err = _err$2._0;
        break _L;
      }
      if (_bind$5 === -1) {
        return;
      } else {
        const _Some = _bind$5;
        const _payload = _Some;
        _cont(_payload);
        return;
      }
    }
    _err_cont(_err);
  }, _err_cont);
  let _tmp$2;
  if (_bind$3.$tag === 1) {
    const _ok = _bind$3;
    _tmp$2 = _ok._0;
  } else {
    return _bind$3;
  }
  const _tmp$3 = _tmp$2;
  if (_tmp$3.$tag === 1) {
    const _Some = _tmp$3;
    const _payload = _Some._0;
    return _M0FP46f4ah6o3dsh7browser2sw20activate__generationN16_2aasync__driverS1231(new _M0DTP46f4ah6o3dsh7browser2sw53_24f4ah6o_2fdsh_2fbrowser_2fsw_2eactivate__generationL5State9State__13(_payload, origin, _cont, _err_cont));
  } else {
    return new _M0DTPC16result6ResultGOuRPC15error5ErrorE2Ok(-1);
  }
}
function _M0FP46f4ah6o3dsh7browser2sw32refresh__shell__generation__workN16_2aasync__driverS1408(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _State_0 = _state$2;
        const candidate = _State_0._1;
        return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(candidate));
      }
      case 1: {
        const _State_1 = _state$2;
        const _err_cont = _State_1._3;
        const _cont = _State_1._2;
        const candidate$2 = _State_1._1;
        const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw26clear__generation__staging(candidate$2, (_cont_param) => {
          let _err;
          _L$2: {
            const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw32refresh__shell__generation__workN16_2aasync__driverS1408(new _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__0(_cont_param, candidate$2));
            let _tmp$3;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _tmp$3 = _ok._0;
            } else {
              const _err$2 = _bind$4;
              _err = _err$2._0;
              break _L$2;
            }
            const _tmp$4 = _tmp$3;
            if (_tmp$4.$tag === 1) {
              const _Some = _tmp$4;
              const _payload = _Some._0;
              _cont(_payload);
              return;
            } else {
              return;
            }
          }
          _err_cont(_err);
        }, _err_cont);
        let _bind$4;
        if (_bind$3.$tag === 1) {
          const _ok = _bind$3;
          _bind$4 = _ok._0;
        } else {
          return _bind$3;
        }
        if (_bind$4 === -1) {
          return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
        } else {
          const _Some = _bind$4;
          const _payload = _Some;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__0(_payload, candidate$2);
          continue _L;
        }
      }
      case 2: {
        return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(undefined));
      }
      case 3: {
        const _State_3 = _state$2;
        const _err_cont$2 = _State_3._3;
        const _cont$2 = _State_3._2;
        const candidate$3 = _State_3._1;
        const _bind$5 = _M0FP46f4ah6o3dsh7browser2sw26clear__generation__staging(candidate$3, (_cont_param) => {
          let _err;
          _L$2: {
            const _bind$6 = _M0FP46f4ah6o3dsh7browser2sw32refresh__shell__generation__workN16_2aasync__driverS1408(new _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__2(_cont_param));
            let _tmp$3;
            if (_bind$6.$tag === 1) {
              const _ok = _bind$6;
              _tmp$3 = _ok._0;
            } else {
              const _err$2 = _bind$6;
              _err = _err$2._0;
              break _L$2;
            }
            const _tmp$4 = _tmp$3;
            if (_tmp$4.$tag === 1) {
              const _Some = _tmp$4;
              const _payload = _Some._0;
              _cont$2(_payload);
              return;
            } else {
              return;
            }
          }
          _err_cont$2(_err);
        }, _err_cont$2);
        let _bind$6;
        if (_bind$5.$tag === 1) {
          const _ok = _bind$5;
          _bind$6 = _ok._0;
        } else {
          return _bind$5;
        }
        if (_bind$6 === -1) {
          return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
        } else {
          const _Some = _bind$6;
          const _payload = _Some;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__2(_payload);
          continue _L;
        }
      }
      case 4: {
        const _State_4 = _state$2;
        const _err_cont$3 = _State_4._3;
        const _cont$3 = _State_4._2;
        const candidate$4 = _State_4._1;
        const _cont_param = _State_4._0;
        if (!_cont_param) {
          const _bind$7 = _M0MP311moonbitlang5async9js__async7Promise4waitGbE(_M0FP46f4ah6o3dsh7browser2sw17sw__cache__delete(candidate$4), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$2) => {
            let _err;
            _L$2: {
              const _bind$8 = _M0FP46f4ah6o3dsh7browser2sw32refresh__shell__generation__workN16_2aasync__driverS1408(new _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__3(_cont_param$2, candidate$4, _cont$3, _err_cont$3));
              let _tmp$3;
              if (_bind$8.$tag === 1) {
                const _ok = _bind$8;
                _tmp$3 = _ok._0;
              } else {
                const _err$2 = _bind$8;
                _err = _err$2._0;
                break _L$2;
              }
              const _tmp$4 = _tmp$3;
              if (_tmp$4.$tag === 1) {
                const _Some = _tmp$4;
                const _payload = _Some._0;
                _cont$3(_payload);
                return;
              } else {
                return;
              }
            }
            _err_cont$3(_err);
          }, _err_cont$3);
          let _bind$8;
          if (_bind$7.$tag === 1) {
            const _ok = _bind$7;
            _bind$8 = _ok._0;
          } else {
            return _bind$7;
          }
          if (_bind$8 === -1) {
            return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
          } else {
            const _Some = _bind$8;
            const _payload = _Some;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__3(_payload, candidate$4, _cont$3, _err_cont$3);
            continue _L;
          }
        } else {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__1(undefined, candidate$4, _cont$3, _err_cont$3);
          continue _L;
        }
      }
      default: {
        const _State_5 = _state$2;
        const _err_cont$4 = _State_5._2;
        const _cont$4 = _State_5._1;
        const _cont_param$2 = _State_5._0;
        if (_cont_param$2 === undefined) {
          return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(undefined));
        } else {
          const _Some = _cont_param$2;
          const _candidate = _Some;
          const _p = _M0FP46f4ah6o3dsh7browser2sw20sw__location__origin();
          const _bind$7 = _M0FP46f4ah6o3dsh7browser2sw15write__metadata(`${_p}${_M0FP46f4ah6o3dsh7browser2sw11active__key}`, _candidate, (_cont_param$3) => {
            let _err;
            _L$2: {
              const _bind$8 = _M0FP46f4ah6o3dsh7browser2sw32refresh__shell__generation__workN16_2aasync__driverS1408(new _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__4(_cont_param$3, _candidate, _cont$4, _err_cont$4));
              let _tmp$3;
              if (_bind$8.$tag === 1) {
                const _ok = _bind$8;
                _tmp$3 = _ok._0;
              } else {
                const _err$2 = _bind$8;
                _err = _err$2._0;
                break _L$2;
              }
              const _tmp$4 = _tmp$3;
              if (_tmp$4.$tag === 1) {
                const _Some$2 = _tmp$4;
                const _payload = _Some$2._0;
                _cont$4(_payload);
                return;
              } else {
                return;
              }
            }
            _err_cont$4(_err);
          }, _err_cont$4);
          let _bind$8;
          if (_bind$7.$tag === 1) {
            const _ok = _bind$7;
            _bind$8 = _ok._0;
          } else {
            return _bind$7;
          }
          if (_bind$8 === -1) {
            return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
          } else {
            const _Some$2 = _bind$8;
            const _payload = _Some$2;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__4(_payload, _candidate, _cont$4, _err_cont$4);
            continue _L;
          }
        }
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw32refresh__shell__generation__work(_cont, _err_cont) {
  const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw25create__shell__generation((_cont_param) => {
    let _err;
    _L: {
      const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw32refresh__shell__generation__workN16_2aasync__driverS1408(new _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__5(_cont_param, _cont, _err_cont));
      let _tmp$2;
      if (_bind$4.$tag === 1) {
        const _ok = _bind$4;
        _tmp$2 = _ok._0;
      } else {
        const _err$2 = _bind$4;
        _err = _err$2._0;
        break _L;
      }
      const _tmp$3 = _tmp$2;
      if (_tmp$3.$tag === 1) {
        const _Some = _tmp$3;
        const _payload = _Some._0;
        _cont(_payload);
        return;
      } else {
        return;
      }
    }
    _err_cont(_err);
  }, _err_cont);
  let _tmp$2;
  if (_bind$3.$tag === 1) {
    const _ok = _bind$3;
    _tmp$2 = _ok._0;
  } else {
    return _bind$3;
  }
  const _tmp$3 = _tmp$2;
  if (_tmp$3.$tag === 1) {
    const _Some = _tmp$3;
    const _payload = _Some._0;
    return _M0FP46f4ah6o3dsh7browser2sw32refresh__shell__generation__workN16_2aasync__driverS1408(new _M0DTP46f4ah6o3dsh7browser2sw65_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generation__workL5State8State__5(_payload, _cont, _err_cont));
  } else {
    return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
  }
}
function _M0FP46f4ah6o3dsh7browser2sw26refresh__shell__generationN16_2aasync__driverS1471(_state) {
  let _tmp$2 = _state;
  while (true) {
    const _state$2 = _tmp$2;
    if (_state$2.$tag === 0) {
      const _State_0 = _state$2;
      const _err_cont = _State_0._3;
      const _cont = _State_0._2;
      const promise = _State_0._1;
      const _cont_param = _State_0._0;
      const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw19refresh__in__flight.val;
      if (_bind$3.$tag === 1) {
        const _Some = _bind$3;
        const _current = _Some._0;
        if (_M0FP46f4ah6o3dsh7browser2sw17sw__same__promise(_current, promise)) {
          _M0FP46f4ah6o3dsh7browser2sw19refresh__in__flight.val = _M0DTPC16option6OptionGRP311moonbitlang5async9js__async7PromiseGOsEE4None__;
        }
      }
      if (_cont_param === undefined) {
        return _M0FP46f4ah6o3dsh7browser2sw24read__active__generation(_cont, _err_cont);
      } else {
        const _Some = _cont_param;
        const _generation = _Some;
        return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(_generation));
      }
    } else {
      const _$42$try$47$399 = _state$2;
      const _err_cont = _$42$try$47$399._3;
      const _cont = _$42$try$47$399._2;
      const promise = _$42$try$47$399._1;
      const _try_err = _$42$try$47$399._0;
      if (_try_err.$tag === 1) {
        return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE3Err(_try_err);
      } else {
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw59_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generationL5State8State__0(undefined, promise, _cont, _err_cont);
        continue;
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw26refresh__shell__generation(_cont, _err_cont) {
  const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw19refresh__in__flight.val;
  let promise;
  if (_bind$3.$tag === 1) {
    const _Some = _bind$3;
    promise = _Some._0;
  } else {
    const created = _M0MP311moonbitlang5async9js__async7Promise11from__asyncGRP46f4ah6o3dsh7browser2sw10SwResponseE((_cont$2, _err_cont$2) => _M0FP46f4ah6o3dsh7browser2sw32refresh__shell__generation__work(_cont$2, _err_cont$2), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async11AbortSignalE4None__);
    _M0FP46f4ah6o3dsh7browser2sw19refresh__in__flight.val = new _M0DTPC16option6OptionGRP311moonbitlang5async9js__async7PromiseGOsEE4Some(created);
    promise = created;
  }
  let _err;
  _L: {
    const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(promise, _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param) => {
      let _err$2;
      _L$2: {
        const _bind$5 = _M0FP46f4ah6o3dsh7browser2sw26refresh__shell__generationN16_2aasync__driverS1471(new _M0DTP46f4ah6o3dsh7browser2sw59_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generationL5State8State__0(_cont_param, promise, _cont, _err_cont));
        let _tmp$2;
        if (_bind$5.$tag === 1) {
          const _ok = _bind$5;
          _tmp$2 = _ok._0;
        } else {
          const _err$3 = _bind$5;
          _err$2 = _err$3._0;
          break _L$2;
        }
        const _tmp$3 = _tmp$2;
        if (_tmp$3.$tag === 1) {
          const _Some = _tmp$3;
          const _payload = _Some._0;
          _cont(_payload);
          return;
        } else {
          return;
        }
      }
      _err_cont(_err$2);
    }, (_cont_param) => {
      let _err$2;
      _L$2: {
        const _bind$5 = _M0FP46f4ah6o3dsh7browser2sw26refresh__shell__generationN16_2aasync__driverS1471(new _M0DTP46f4ah6o3dsh7browser2sw59_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generationL5State12_2atry_2f399(_cont_param, promise, _cont, _err_cont));
        let _tmp$2;
        if (_bind$5.$tag === 1) {
          const _ok = _bind$5;
          _tmp$2 = _ok._0;
        } else {
          const _err$3 = _bind$5;
          _err$2 = _err$3._0;
          break _L$2;
        }
        const _tmp$3 = _tmp$2;
        if (_tmp$3.$tag === 1) {
          const _Some = _tmp$3;
          const _payload = _Some._0;
          _cont(_payload);
          return;
        } else {
          return;
        }
      }
      _err_cont(_err$2);
    });
    let _tmp$2;
    if (_bind$4.$tag === 1) {
      const _ok = _bind$4;
      _tmp$2 = _ok._0;
    } else {
      const _err$2 = _bind$4;
      _err = _err$2._0;
      break _L;
    }
    const _tmp$3 = _tmp$2;
    if (_tmp$3.$tag === 1) {
      const _Some = _tmp$3;
      const _payload = _Some._0;
      return _M0FP46f4ah6o3dsh7browser2sw26refresh__shell__generationN16_2aasync__driverS1471(new _M0DTP46f4ah6o3dsh7browser2sw59_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generationL5State8State__0(_payload, promise, _cont, _err_cont));
    } else {
      return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
    }
  }
  return _M0FP46f4ah6o3dsh7browser2sw26refresh__shell__generationN16_2aasync__driverS1471(new _M0DTP46f4ah6o3dsh7browser2sw59_24f4ah6o_2fdsh_2fbrowser_2fsw_2erefresh__shell__generationL5State12_2atry_2f399(_err, promise, _cont, _err_cont));
}
function _M0FP46f4ah6o3dsh7browser2sw23generation__for__clientN16_2aasync__driverS1503(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _State_0 = _state$2;
        const _err_cont = _State_0._2;
        const _cont = _State_0._1;
        const _cont_param = _State_0._0;
        if (_cont_param === undefined) {
          return _M0FP46f4ah6o3dsh7browser2sw24find__legacy__generation(_cont, _err_cont);
        } else {
          const _Some = _cont_param;
          const _active = _Some;
          return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(_active));
        }
      }
      case 1: {
        const _$42$arm$47$415 = _state$2;
        const _err_cont$2 = _$42$arm$47$415._1;
        const _cont$2 = _$42$arm$47$415._0;
        const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw24read__active__generation((_cont_param$2) => {
          let _err;
          _L$2: {
            const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw23generation__for__clientN16_2aasync__driverS1503(new _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State8State__0(_cont_param$2, _cont$2, _err_cont$2));
            let _tmp$3;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _tmp$3 = _ok._0;
            } else {
              const _err$2 = _bind$4;
              _err = _err$2._0;
              break _L$2;
            }
            const _tmp$4 = _tmp$3;
            if (_tmp$4.$tag === 1) {
              const _Some = _tmp$4;
              const _payload = _Some._0;
              _cont$2(_payload);
              return;
            } else {
              return;
            }
          }
          _err_cont$2(_err);
        }, _err_cont$2);
        let _tmp$3;
        if (_bind$3.$tag === 1) {
          const _ok = _bind$3;
          _tmp$3 = _ok._0;
        } else {
          return _bind$3;
        }
        const _tmp$4 = _tmp$3;
        if (_tmp$4.$tag === 1) {
          const _Some = _tmp$4;
          const _payload = _Some._0;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State8State__0(_payload, _cont$2, _err_cont$2);
          continue _L;
        } else {
          return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
        }
      }
      case 2: {
        const _State_2 = _state$2;
        const _err_cont$3 = _State_2._3;
        const _cont$3 = _State_2._2;
        const _pinned = _State_2._1;
        const _cont_param$2 = _State_2._0;
        if (_M0MPC15array5Array8containsGsE(_cont_param$2, _pinned)) {
          return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGOsE4Some(_pinned));
        } else {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State12_2aarm_2f415(_cont$3, _err_cont$3);
          continue _L;
        }
      }
      default: {
        const _State_3 = _state$2;
        const _err_cont$4 = _State_3._2;
        const _cont$4 = _State_3._1;
        const _cont_param$3 = _State_3._0;
        if (_cont_param$3 === undefined) {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State12_2aarm_2f415(_cont$4, _err_cont$4);
          continue _L;
        } else {
          const _Some = _cont_param$3;
          const _pinned$2 = _Some;
          const _bind$4 = _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(_M0FP46f4ah6o3dsh7browser2sw16sw__cache__names(), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$4) => {
            let _err;
            _L$2: {
              const _bind$5 = _M0FP46f4ah6o3dsh7browser2sw23generation__for__clientN16_2aasync__driverS1503(new _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State8State__2(_cont_param$4, _pinned$2, _cont$4, _err_cont$4));
              let _tmp$5;
              if (_bind$5.$tag === 1) {
                const _ok = _bind$5;
                _tmp$5 = _ok._0;
              } else {
                const _err$2 = _bind$5;
                _err = _err$2._0;
                break _L$2;
              }
              const _tmp$6 = _tmp$5;
              if (_tmp$6.$tag === 1) {
                const _Some$2 = _tmp$6;
                const _payload = _Some$2._0;
                _cont$4(_payload);
                return;
              } else {
                return;
              }
            }
            _err_cont$4(_err);
          }, _err_cont$4);
          let _tmp$5;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _tmp$5 = _ok._0;
          } else {
            return _bind$4;
          }
          const _tmp$6 = _tmp$5;
          if (_tmp$6.$tag === 1) {
            const _Some$2 = _tmp$6;
            const _payload = _Some$2._0;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State8State__2(_payload, _pinned$2, _cont$4, _err_cont$4);
            continue _L;
          } else {
            return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
          }
        }
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw23generation__for__client(client_id, _cont, _err_cont) {
  const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw24read__client__generation(client_id, (_cont_param) => {
    let _err;
    _L: {
      const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw23generation__for__clientN16_2aasync__driverS1503(new _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State8State__3(_cont_param, _cont, _err_cont));
      let _tmp$2;
      if (_bind$4.$tag === 1) {
        const _ok = _bind$4;
        _tmp$2 = _ok._0;
      } else {
        const _err$2 = _bind$4;
        _err = _err$2._0;
        break _L;
      }
      const _tmp$3 = _tmp$2;
      if (_tmp$3.$tag === 1) {
        const _Some = _tmp$3;
        const _payload = _Some._0;
        _cont(_payload);
        return;
      } else {
        return;
      }
    }
    _err_cont(_err);
  }, _err_cont);
  let _tmp$2;
  if (_bind$3.$tag === 1) {
    const _ok = _bind$3;
    _tmp$2 = _ok._0;
  } else {
    return _bind$3;
  }
  const _tmp$3 = _tmp$2;
  if (_tmp$3.$tag === 1) {
    const _Some = _tmp$3;
    const _payload = _Some._0;
    return _M0FP46f4ah6o3dsh7browser2sw23generation__for__clientN16_2aasync__driverS1503(new _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2egeneration__for__clientL5State8State__3(_payload, _cont, _err_cont));
  } else {
    return new _M0DTPC16result6ResultGOOsRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGOsE4None__);
  }
}
function _M0FP46f4ah6o3dsh7browser2sw23serve__from__generationN16_2aasync__driverS1544(_state) {
  let _tmp$2 = _state;
  while (true) {
    const _state$2 = _tmp$2;
    if (_state$2.$tag === 0) {
      const _State_0 = _state$2;
      const _err_cont = _State_0._4;
      const _cont = _State_0._3;
      const cache = _State_0._2;
      const url = _State_0._1;
      const _cont_param = _State_0._0;
      return _cont_param ? _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(_M0FP46f4ah6o3dsh7browser2sw16sw__cache__match(cache, url), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, _cont, _err_cont) : new _M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4Some(_M0FP46f4ah6o3dsh7browser2sw32sw__text__response__with__status(503, "The app shell asset is unavailable.", _M0FP46f4ah6o3dsh7browser2sw19text__content__type)));
    } else {
      const _State_1 = _state$2;
      const _err_cont = _State_1._3;
      const _cont = _State_1._2;
      const url = _State_1._1;
      const _cont_param = _State_1._0;
      const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGbE(_M0FP46f4ah6o3dsh7browser2sw14sw__cache__has(_cont_param, url), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param$2) => {
        let _err;
        _L: {
          const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw23serve__from__generationN16_2aasync__driverS1544(new _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2eserve__from__generationL5State8State__0(_cont_param$2, url, _cont_param, _cont, _err_cont));
          let _tmp$3;
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            _tmp$3 = _ok._0;
          } else {
            const _err$2 = _bind$4;
            _err = _err$2._0;
            break _L;
          }
          const _tmp$4 = _tmp$3;
          if (_tmp$4.$tag === 1) {
            const _Some = _tmp$4;
            const _payload = _Some._0;
            _cont(_payload);
            return;
          } else {
            return;
          }
        }
        _err_cont(_err);
      }, _err_cont);
      let _bind$4;
      if (_bind$3.$tag === 1) {
        const _ok = _bind$3;
        _bind$4 = _ok._0;
      } else {
        return _bind$3;
      }
      if (_bind$4 === -1) {
        return new _M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4None__);
      } else {
        const _Some = _bind$4;
        const _payload = _Some;
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2eserve__from__generationL5State8State__0(_payload, url, _cont_param, _cont, _err_cont);
        continue;
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw23serve__from__generation(url, generation, _cont, _err_cont) {
  if (generation === undefined) {
    return new _M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok(new _M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4Some(_M0FP46f4ah6o3dsh7browser2sw32sw__text__response__with__status(503, "The app shell is unavailable offline.", _M0FP46f4ah6o3dsh7browser2sw19text__content__type)));
  } else {
    const _Some = generation;
    const _name = _Some;
    const _bind$3 = _M0MP311moonbitlang5async9js__async7Promise4waitGRPB5ArrayGsEE(_M0FP46f4ah6o3dsh7browser2sw15sw__cache__open(_name), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async15AbortControllerE4None__, (_cont_param) => {
      let _err;
      _L: {
        const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw23serve__from__generationN16_2aasync__driverS1544(new _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2eserve__from__generationL5State8State__1(_cont_param, url, _cont, _err_cont));
        let _tmp$2;
        if (_bind$4.$tag === 1) {
          const _ok = _bind$4;
          _tmp$2 = _ok._0;
        } else {
          const _err$2 = _bind$4;
          _err = _err$2._0;
          break _L;
        }
        const _tmp$3 = _tmp$2;
        if (_tmp$3.$tag === 1) {
          const _Some$2 = _tmp$3;
          const _payload = _Some$2._0;
          _cont(_payload);
          return;
        } else {
          return;
        }
      }
      _err_cont(_err);
    }, _err_cont);
    let _tmp$2;
    if (_bind$3.$tag === 1) {
      const _ok = _bind$3;
      _tmp$2 = _ok._0;
    } else {
      return _bind$3;
    }
    const _tmp$3 = _tmp$2;
    if (_tmp$3.$tag === 1) {
      const _Some$2 = _tmp$3;
      const _payload = _Some$2._0;
      return _M0FP46f4ah6o3dsh7browser2sw23serve__from__generationN16_2aasync__driverS1544(new _M0DTP46f4ah6o3dsh7browser2sw56_24f4ah6o_2fdsh_2fbrowser_2fsw_2eserve__from__generationL5State8State__1(_payload, url, _cont, _err_cont));
    } else {
      return new _M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4None__);
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw22handle__shell__requestN16_2aasync__driverS1573(_state) {
  let _tmp$2 = _state;
  _L: while (true) {
    const _state$2 = _tmp$2;
    switch (_state$2.$tag) {
      case 0: {
        const _State_0 = _state$2;
        const _err_cont = _State_0._3;
        const _cont = _State_0._2;
        const url = _State_0._1;
        const _cont_param = _State_0._0;
        return _M0FP46f4ah6o3dsh7browser2sw23serve__from__generation(url, _cont_param, _cont, _err_cont);
      }
      case 1: {
        const _State_1 = _state$2;
        const _err_cont$2 = _State_1._4;
        const _cont$2 = _State_1._3;
        const selected = _State_1._2;
        const url$2 = _State_1._1;
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__0(selected, url$2, _cont$2, _err_cont$2);
        continue _L;
      }
      case 2: {
        const _State_2 = _state$2;
        const _err_cont$3 = _State_2._5;
        const _cont$3 = _State_2._4;
        const selected$2 = _State_2._3;
        const target_client_id = _State_2._2;
        const url$3 = _State_2._1;
        const additional = target_client_id === "" ? [] : [target_client_id];
        const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw25cleanup__old__generations(additional, (_cont_param$2) => {
          let _err;
          _L$2: {
            const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw22handle__shell__requestN16_2aasync__driverS1573(new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__1(_cont_param$2, url$3, selected$2, _cont$3, _err_cont$3));
            let _tmp$3;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              _tmp$3 = _ok._0;
            } else {
              const _err$2 = _bind$4;
              _err = _err$2._0;
              break _L$2;
            }
            const _tmp$4 = _tmp$3;
            if (_tmp$4.$tag === 1) {
              const _Some = _tmp$4;
              const _payload = _Some._0;
              _cont$3(_payload);
              return;
            } else {
              return;
            }
          }
          _err_cont$3(_err);
        }, _err_cont$3);
        let _bind$4;
        if (_bind$3.$tag === 1) {
          const _ok = _bind$3;
          _bind$4 = _ok._0;
        } else {
          return _bind$3;
        }
        if (_bind$4 === -1) {
          return new _M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4None__);
        } else {
          const _Some = _bind$4;
          const _payload = _Some;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__1(_payload, url$3, selected$2, _cont$3, _err_cont$3);
          continue _L;
        }
      }
      case 3: {
        const _State_3 = _state$2;
        const _err_cont$4 = _State_3._5;
        const _cont$4 = _State_3._4;
        const selected$3 = _State_3._3;
        const target_client_id$2 = _State_3._2;
        const url$4 = _State_3._1;
        _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__2(undefined, url$4, target_client_id$2, selected$3, _cont$4, _err_cont$4);
        continue _L;
      }
      case 4: {
        const _State_4 = _state$2;
        const _err_cont$5 = _State_4._4;
        const _cont$5 = _State_4._3;
        const target_client_id$3 = _State_4._2;
        const url$5 = _State_4._1;
        const _cont_param$2 = _State_4._0;
        if (target_client_id$3 === "") {
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__2(undefined, url$5, target_client_id$3, _cont_param$2, _cont$5, _err_cont$5);
          continue _L;
        } else {
          if (_cont_param$2 === undefined) {
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__2(undefined, url$5, target_client_id$3, _cont_param$2, _cont$5, _err_cont$5);
            continue _L;
          } else {
            const _Some = _cont_param$2;
            const _name = _Some;
            const _bind$5 = _M0FP46f4ah6o3dsh7browser2sw15write__metadata(_M0FP46f4ah6o3dsh7browser2sw22encoded__metadata__key(_M0FP46f4ah6o3dsh7browser2sw20sw__location__origin(), _M0FP46f4ah6o3dsh7browser2sw19client__pin__prefix, target_client_id$3), _name, (_cont_param$3) => {
              let _err;
              _L$2: {
                const _bind$6 = _M0FP46f4ah6o3dsh7browser2sw22handle__shell__requestN16_2aasync__driverS1573(new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__3(_cont_param$3, url$5, target_client_id$3, _cont_param$2, _cont$5, _err_cont$5));
                let _tmp$3;
                if (_bind$6.$tag === 1) {
                  const _ok = _bind$6;
                  _tmp$3 = _ok._0;
                } else {
                  const _err$2 = _bind$6;
                  _err = _err$2._0;
                  break _L$2;
                }
                const _tmp$4 = _tmp$3;
                if (_tmp$4.$tag === 1) {
                  const _Some$2 = _tmp$4;
                  const _payload = _Some$2._0;
                  _cont$5(_payload);
                  return;
                } else {
                  return;
                }
              }
              _err_cont$5(_err);
            }, _err_cont$5);
            let _bind$6;
            if (_bind$5.$tag === 1) {
              const _ok = _bind$5;
              _bind$6 = _ok._0;
            } else {
              return _bind$5;
            }
            if (_bind$6 === -1) {
              return new _M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4None__);
            } else {
              const _Some$2 = _bind$6;
              const _payload = _Some$2;
              _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__3(_payload, url$5, target_client_id$3, _cont_param$2, _cont$5, _err_cont$5);
              continue _L;
            }
          }
        }
      }
      default: {
        const _State_5 = _state$2;
        const _err_cont$6 = _State_5._5;
        const _cont$6 = _State_5._4;
        const target_client_id$4 = _State_5._3;
        const client_id = _State_5._2;
        const url$6 = _State_5._1;
        const _cont_param$3 = _State_5._0;
        if (_cont_param$3 === undefined) {
          const _bind$5 = _M0FP46f4ah6o3dsh7browser2sw23generation__for__client(client_id, (_cont_param$4) => {
            let _err;
            _L$2: {
              const _bind$6 = _M0FP46f4ah6o3dsh7browser2sw22handle__shell__requestN16_2aasync__driverS1573(new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__4(_cont_param$4, url$6, target_client_id$4, _cont$6, _err_cont$6));
              let _tmp$3;
              if (_bind$6.$tag === 1) {
                const _ok = _bind$6;
                _tmp$3 = _ok._0;
              } else {
                const _err$2 = _bind$6;
                _err = _err$2._0;
                break _L$2;
              }
              const _tmp$4 = _tmp$3;
              if (_tmp$4.$tag === 1) {
                const _Some = _tmp$4;
                const _payload = _Some._0;
                _cont$6(_payload);
                return;
              } else {
                return;
              }
            }
            _err_cont$6(_err);
          }, _err_cont$6);
          let _tmp$3;
          if (_bind$5.$tag === 1) {
            const _ok = _bind$5;
            _tmp$3 = _ok._0;
          } else {
            return _bind$5;
          }
          const _tmp$4 = _tmp$3;
          if (_tmp$4.$tag === 1) {
            const _Some = _tmp$4;
            const _payload = _Some._0;
            _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__4(_payload, url$6, target_client_id$4, _cont$6, _err_cont$6);
            continue _L;
          } else {
            return new _M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4None__);
          }
        } else {
          const _Some = _cont_param$3;
          const _name = _Some;
          _tmp$2 = new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__4(_name, url$6, target_client_id$4, _cont$6, _err_cont$6);
          continue _L;
        }
      }
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw22handle__shell__request(event, url, _cont, _err_cont) {
  const request = _M0FP46f4ah6o3dsh7browser2sw18sw__event__request(event);
  const client_id = _M0FP46f4ah6o3dsh7browser2sw21sw__event__client__id(event);
  const _bind$3 = _M0FP46f4ah6o3dsh7browser2sw32sw__event__resulting__client__id(event);
  let target_client_id;
  if (_bind$3 === "") {
    target_client_id = client_id;
  } else {
    target_client_id = _bind$3;
  }
  if (_M0FP46f4ah6o3dsh7browser2sw17sw__request__mode(request) === "navigate") {
    const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw26refresh__shell__generation((_cont_param) => {
      let _err;
      _L: {
        const _bind$5 = _M0FP46f4ah6o3dsh7browser2sw22handle__shell__requestN16_2aasync__driverS1573(new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__5(_cont_param, url, client_id, target_client_id, _cont, _err_cont));
        let _tmp$2;
        if (_bind$5.$tag === 1) {
          const _ok = _bind$5;
          _tmp$2 = _ok._0;
        } else {
          const _err$2 = _bind$5;
          _err = _err$2._0;
          break _L;
        }
        const _tmp$3 = _tmp$2;
        if (_tmp$3.$tag === 1) {
          const _Some = _tmp$3;
          const _payload = _Some._0;
          _cont(_payload);
          return;
        } else {
          return;
        }
      }
      _err_cont(_err);
    }, _err_cont);
    let _tmp$2;
    if (_bind$4.$tag === 1) {
      const _ok = _bind$4;
      _tmp$2 = _ok._0;
    } else {
      return _bind$4;
    }
    const _tmp$3 = _tmp$2;
    if (_tmp$3.$tag === 1) {
      const _Some = _tmp$3;
      const _payload = _Some._0;
      return _M0FP46f4ah6o3dsh7browser2sw22handle__shell__requestN16_2aasync__driverS1573(new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__5(_payload, url, client_id, target_client_id, _cont, _err_cont));
    } else {
      return new _M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4None__);
    }
  } else {
    const _bind$4 = _M0FP46f4ah6o3dsh7browser2sw23generation__for__client(client_id, (_cont_param) => {
      let _err;
      _L: {
        const _bind$5 = _M0FP46f4ah6o3dsh7browser2sw22handle__shell__requestN16_2aasync__driverS1573(new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__0(_cont_param, url, _cont, _err_cont));
        let _tmp$2;
        if (_bind$5.$tag === 1) {
          const _ok = _bind$5;
          _tmp$2 = _ok._0;
        } else {
          const _err$2 = _bind$5;
          _err = _err$2._0;
          break _L;
        }
        const _tmp$3 = _tmp$2;
        if (_tmp$3.$tag === 1) {
          const _Some = _tmp$3;
          const _payload = _Some._0;
          _cont(_payload);
          return;
        } else {
          return;
        }
      }
      _err_cont(_err);
    }, _err_cont);
    let _tmp$2;
    if (_bind$4.$tag === 1) {
      const _ok = _bind$4;
      _tmp$2 = _ok._0;
    } else {
      return _bind$4;
    }
    const _tmp$3 = _tmp$2;
    if (_tmp$3.$tag === 1) {
      const _Some = _tmp$3;
      const _payload = _Some._0;
      return _M0FP46f4ah6o3dsh7browser2sw22handle__shell__requestN16_2aasync__driverS1573(new _M0DTP46f4ah6o3dsh7browser2sw55_24f4ah6o_2fdsh_2fbrowser_2fsw_2ehandle__shell__requestL5State8State__0(_payload, url, _cont, _err_cont));
    } else {
      return new _M0DTPC16result6ResultGORP46f4ah6o3dsh7browser2sw10SwResponseRPC15error5ErrorE2Ok(_M0DTPC16option6OptionGRP46f4ah6o3dsh7browser2sw10SwResponseE4None__);
    }
  }
}
function _M0FP46f4ah6o3dsh7browser2sw22handle__install__event(event) {
  _M0FP46f4ah6o3dsh7browser2sw22sw__event__wait__until(event, _M0MP311moonbitlang5async9js__async7Promise11from__asyncGuE((_cont, _err_cont) => _M0FP46f4ah6o3dsh7browser2sw19stage__for__install(_cont, _err_cont), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async11AbortSignalE4None__));
  _M0FP46f4ah6o3dsh7browser2sw17sw__skip__waiting();
}
function _M0FP46f4ah6o3dsh7browser2sw23handle__activate__event(event) {
  _M0FP46f4ah6o3dsh7browser2sw22sw__event__wait__until(event, _M0MP311moonbitlang5async9js__async7Promise11from__asyncGuE((_cont, _err_cont) => _M0FP46f4ah6o3dsh7browser2sw20activate__generation(_cont, _err_cont), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async11AbortSignalE4None__));
}
function _M0FP46f4ah6o3dsh7browser2sw20handle__fetch__event(event) {
  const request = _M0FP46f4ah6o3dsh7browser2sw18sw__event__request(event);
  let _tmp$2;
  const _p = _M0FP46f4ah6o3dsh7browser2sw19sw__request__method(request);
  const _p$2 = "GET";
  if (!(_p === _p$2)) {
    _tmp$2 = true;
  } else {
    _tmp$2 = _M0FP46f4ah6o3dsh7browser2sw24sw__request__has__header(request, "authorization");
  }
  if (_tmp$2) {
    return undefined;
  }
  const request_url = _M0FP46f4ah6o3dsh7browser2sw16sw__request__url(request);
  const origin = _M0FP46f4ah6o3dsh7browser2sw15sw__url__origin(request_url);
  const _p$3 = _M0FP46f4ah6o3dsh7browser2sw20sw__location__origin();
  if (!(origin === _p$3)) {
    return undefined;
  }
  const path = _M0FP46f4ah6o3dsh7browser2sw13sw__url__path(request_url);
  let _tmp$3;
  if (!_M0MPC15array13ReadOnlyArray8containsGsE(_M0FP46f4ah6o3dsh7browser2sw13shell__assets, path)) {
    _tmp$3 = true;
  } else {
    const _p$4 = _M0FP46f4ah6o3dsh7browser2sw15sw__url__search(request_url);
    const _p$5 = "";
    _tmp$3 = !(_p$4 === _p$5);
  }
  if (_tmp$3) {
    return undefined;
  }
  _M0FP46f4ah6o3dsh7browser2sw24sw__event__respond__with(event, _M0MP311moonbitlang5async9js__async7Promise11from__asyncGRP46f4ah6o3dsh7browser2sw10SwResponseE((_cont, _err_cont) => _M0FP46f4ah6o3dsh7browser2sw22handle__shell__request(event, `${origin}${path}`, _cont, _err_cont), _M0DTPC16option6OptionGRP311moonbitlang5async9js__async11AbortSignalE4None__));
}
function _M0FP46f4ah6o3dsh7browser2sw22start__service__worker() {
  if (!_M0FP46f4ah6o3dsh7browser2sw13sw__available()) {
    return false;
  }
  _M0FP46f4ah6o3dsh7browser2sw24sw__add__event__listener("install", _M0FP46f4ah6o3dsh7browser2sw22handle__install__event);
  _M0FP46f4ah6o3dsh7browser2sw24sw__add__event__listener("activate", _M0FP46f4ah6o3dsh7browser2sw23handle__activate__event);
  _M0FP46f4ah6o3dsh7browser2sw24sw__add__event__listener("fetch", _M0FP46f4ah6o3dsh7browser2sw20handle__fetch__event);
  return true;
}
export { _M0FP46f4ah6o3dsh7browser2sw22start__service__worker as start_service_worker }
