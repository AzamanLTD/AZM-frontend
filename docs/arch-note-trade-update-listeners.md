# Trade update listener boundary

`SocketService` owns the single Socket.IO connection and exposes additive listener registration for global `trade_update` events. Feature screens must unregister their callback on disposal; per-trade message/socket transport remains screen-scoped where required by the chat component.
