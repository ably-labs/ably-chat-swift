import Foundation

struct Schema {
    static var json: [JSON] = {
        do {
            return try JSONSerialization.jsonObject(with: Self.content.data(using: .utf8)!) as! [JSON]
        } catch {
            print("Couldn't parse schema JSON.")
            return []
        }
    }()
}

extension Schema {
    static let content =
"""
[
  {
    "name": "ChatClient",
    "konstructor": {
      "args": {
        "realtimeClientOptions": {
          "type": "RealtimeClientOptions",
          "serializable": true
        },
        "clientOptions": {
          "type": "ClientOptions",
          "serializable": true,
          "optional": true
        }
      }
    },
    "fields": {
      "rooms": {
        "type": "Rooms",
        "serializable": false
      },
      "connection": {
        "type": "Connection",
        "serializable": false
      },
      "clientId": {
        "type": "string",
        "serializable": true
      },
      "realtime": {
        "type": "Realtime",
        "serializable": false
      },
      "clientOptions": {
        "type": "ClientOptions",
        "serializable": true
      },
      "logger": {
        "type": "Logger",
        "serializable": false
      }
    },
    "syncMethods": {
      "addReactAgent": {
        "result": {
          "type": "void"
        }
      }
    }
  },
  {
    "name": "ConnectionStatus",
    "fields": {
      "current": {
        "type": "string",
        "serializable": true
      },
      "error": {
        "type": "ErrorInfo",
        "serializable": true
      }
    },
    "syncMethods": {
      "offAll": {
        "result": {
          "type": "void"
        }
      }
    },
    "listeners": {
      "onChange": {
        "args": {
          "listener": {
            "type": "callback",
            "args": {
              "change": {
                "type": "ConnectionStatusChange",
                "serializable": true
              }
            },
            "result": {
              "type": "void"
            }
          }
        },
        "result": {
          "type": "OnConnectionStatusChangeResponse",
          "serializable": false
        }
      }
    }
  },
  {
    "name": "OnConnectionStatusChangeResponse",
    "syncMethods": {
      "off": {
        "result": {
          "type": "void"
        }
      }
    }
  },
  {
    "name": "Connection",
    "fields": {
      "status": {
        "type": "ConnectionStatus",
        "serializable": false
      }
    }
  },
  {
    "name": "Logger",
    "syncMethods": {
      "trace": {
        "args": {
          "message": {
            "type": "string",
            "serializable": true
          },
          "context": {
            "type": "object",
            "serializable": true,
            "optional": true
          }
        },
        "result": {
          "type": "void"
        }
      },
      "debug": {
        "args": {
          "message": {
            "type": "string",
            "serializable": true
          },
          "context": {
            "type": "object",
            "serializable": true,
            "optional": true
          }
        },
        "result": {
          "type": "void"
        }
      },
      "info": {
        "args": {
          "message": {
            "type": "string",
            "serializable": true
          },
          "context": {
            "type": "object",
            "serializable": true,
            "optional": true
          }
        },
        "result": {
          "type": "void"
        }
      },
      "warn": {
        "args": {
          "message": {
            "type": "string",
            "serializable": true
          },
          "context": {
            "type": "object",
            "serializable": true,
            "optional": true
          }
        },
        "result": {
          "type": "void"
        }
      },
      "error": {
        "args": {
          "message": {
            "type": "string",
            "serializable": true
          },
          "context": {
            "type": "object",
            "serializable": true,
            "optional": true
          }
        },
        "result": {
          "type": "void"
        }
      }
    }
  },
  {
    "name": "Message",
    "fields": {
      "timeserial": {
        "type": "string",
        "serializable": true
      },
      "clientId": {
        "type": "string",
        "serializable": true
      },
      "roomId": {
        "type": "string",
        "serializable": true
      },
      "text": {
        "type": "string",
        "serializable": true
      },
      "createdAt": {
        "type": "number",
        "serializable": true
      },
      "metadata": {
        "type": "object",
        "serializable": true
      },
      "headers": {
        "type": "object",
        "serializable": true
      }
    },
    "syncMethods": {
      "before": {
        "args": {
          "message": {
            "type": "Message",
            "serializable": false
          }
        },
        "result": {
          "type": "boolean"
        }
      },
      "after": {
        "args": {
          "message": {
            "type": "Message",
            "serializable": false
          }
        },
        "result": {
          "type": "boolean"
        }
      },
      "equal": {
        "args": {
          "message": {
            "type": "Message",
            "serializable": false
          }
        },
        "result": {
          "type": "boolean"
        }
      }
    }
  },
  {
    "name": "Messages",
    "fields": {
      "channel": {
        "type": "RealtimeChannel",
        "serializable": false
      }
    },
    "syncMethods": {
      "unsubscribeAll": {
        "result": {
          "type": "void"
        }
      }
    },
    "asyncMethods": {
      "get": {
        "args": {
          "options": {
            "type": "QueryOptions",
            "serializable": true
          }
        },
        "result": {
          "type": "PaginatedResultMessage",
          "serializable": false
        }
      },
      "send": {
        "args": {
          "options": {
            "type": "SendMessageParams",
            "serializable": true
          }
        },
        "result": {
          "type": "Message",
          "serializable": false
        }
      }
    },
    "listeners": {
      "subscribe": {
        "args": {
          "listener": {
            "type": "callback",
            "args": {
              "event": {
                "type": "MessageEventPayload",
                "serializable": false
              }
            },
            "result": {
              "type": "void"
            }
          }
        },
        "result": {
          "type": "MessageSubscriptionResponse",
          "serializable": false
        }
      },
      "onDiscontinuity": {
        "args": {
          "listener": {
            "type": "callback",
            "args": {
              "reason": {
                "type": "AblyErrorInfo",
                "serializable": true,
                "optional": true
              }
            },
            "result": {
              "type": "void"
            }
          }
        },
        "result": {
          "type": "OnDiscontinuitySubscriptionResponse",
          "serializable": false
        }
      }
    }
  },
  {
    "name": "MessageSubscriptionResponse",
    "syncMethods": {
      "unsubscribe": {
        "result": {
          "type": "void"
        }
      }
    },
    "asyncMethods": {
      "getPreviousMessages": {
        "args": {
          "params": {
            "type": "QueryOptions",
            "serializable": true
          }
        },
        "result": {
          "type": "PaginatedResultMessage",
          "serializable": false
        }
      }
    }
  },
  {
    "name": "Occupancy",
    "fields": {
      "channel": {
        "type": "RealtimeChannel",
        "serializable": false
      }
    },
    "syncMethods": {
      "unsubscribeAll": {
        "result": {
          "type": "void"
        }
      }
    },
    "asyncMethods": {
      "get": {
        "result": {
          "type": "OccupancyEvent",
          "serializable": true
        }
      }
    },
    "listeners": {
      "subscribe": {
        "args": {
          "listener": {
            "type": "callback",
            "args": {
              "event": {
                "type": "OccupancyEvent",
                "serializable": true
              }
            },
            "result": {
              "type": "void"
            }
          }
        },
        "result": {
          "type": "OccupancySubscriptionResponse",
          "serializable": false
        }
      },
      "onDiscontinuity": {
        "args": {
          "listener": {
            "type": "callback",
            "args": {
              "reason": {
                "type": "AblyErrorInfo",
                "serializable": true,
                "optional": true
              }
            },
            "result": {
              "type": "void"
            }
          }
        },
        "result": {
          "type": "OnDiscontinuitySubscriptionResponse",
          "serializable": false
        }
      }
    }
  },
  {
    "name": "OccupancySubscriptionResponse",
    "syncMethods": {
      "unsubscribe": {
        "result": {
          "type": "void"
        }
      }
    }
  },
  {
    "name": "OnDiscontinuitySubscriptionResponse",
    "syncMethods": {
      "off": {
        "result": {
          "type": "void"
        }
      }
    }
  },
  {
    "name": "PaginatedResult",
    "fields": {
      "items": {
        "type": "object",
        "serializable": true,
        "array": true
      }
    },
    "syncMethods": {
      "hasNext": {
        "result": {
          "type": "boolean"
        }
      },
      "isLast": {
        "result": {
          "type": "boolean"
        }
      }
    },
    "asyncMethods": {
      "next": {
        "result": {
          "type": "PaginatedResult",
          "serializable": false
        }
      },
      "first": {
        "result": {
          "type": "PaginatedResult",
          "serializable": false
        }
      },
      "current": {
        "result": {
          "type": "PaginatedResult",
          "serializable": false
        }
      }
    }
  },
  {
    "name": "Presence",
    "fields": {
      "channel": {
        "type": "RealtimeChannel",
        "serializable": false
      }
    },
    "syncMethods": {
      "unsubscribeAll": {
        "result": {
          "type": "void"
        }
      }
    },
    "asyncMethods": {
      "get": {
        "args": {
          "params": {
            "type": "RealtimePresenceParams",
            "serializable": true,
            "optional": true
          }
        },
        "result": {
          "type": "PresenceMember",
          "serializable": true,
          "array": true
        }
      },
      "isUserPresent": {
        "args": {
          "clientId": {
            "type": "string",
            "serializable": true
          }
        },
        "result": {
          "type": "boolean",
          "serializable": true
        }
      },
      "enter": {
        "args": {
          "data": {
            "type": "PresenceData",
            "serializable": true,
            "optional": true
          }
        },
        "result": {
          "type": "void"
        }
      },
      "update": {
        "args": {
          "data": {
            "type": "PresenceData",
            "serializable": true,
            "optional": true
          }
        },
        "result": {
          "type": "void"
        }
      },
      "leave": {
        "args": {
          "data": {
            "type": "PresenceData",
            "serializable": true,
            "optional": true
          }
        },
        "result": {
          "type": "void"
        }
      }
    },
    "listeners": {
      "subscribe_listener": {
        "args": {
          "listener": {
            "type": "callback",
            "args": {
              "event": {
                "type": "PresenceEvent",
                "serializable": true
              }
            },
            "result": {
              "type": "void"
            }
          }
        },
        "result": {
          "type": "PresenceSubscriptionResponse",
          "serializable": false
        }
      },
      "subscribe_eventsAndListener": {
        "args": {
          "events": {
            "type": "string",
            "array": true,
            "serializable": true
          },
          "listener": {
            "type": "callback",
            "args": {
              "event": {
                "type": "PresenceEvent",
                "serializable": true
              }
            },
            "result": {
              "type": "void"
            }
          }
        },
        "result": {
          "type": "PresenceSubscriptionResponse",
          "serializable": false
        }
      },
      "onDiscontinuity": {
        "args": {
          "listener": {
            "type": "callback",
            "args": {
              "reason": {
                "type": "AblyErrorInfo",
                "serializable": true,
                "optional": true
              }
            },
            "result": {
              "type": "void"
            }
          }
        },
        "result": {
          "type": "OnDiscontinuitySubscriptionResponse",
          "serializable": false
        }
      }
    }
  },
  {
    "name": "PresenceSubscriptionResponse",
    "syncMethods": {
      "unsubscribe": {
        "result": {
          "type": "void"
        }
      }
    }
  },
  {
    "name": "RoomReactions",
    "fields": {
      "channel": {
        "type": "RealtimeChannel",
        "serializable": false
      }
    },
    "syncMethods": {
      "unsubscribeAll": {
        "result": {
          "type": "void"
        }
      }
    },
    "asyncMethods": {
      "send": {
        "args": {
          "params": {
            "type": "SendReactionParams",
            "serializable": true
          }
        },
        "result": {
          "type": "void"
        }
      }
    },
    "listeners": {
      "subscribe": {
        "args": {
          "listener": {
            "type": "callback",
            "args": {
              "reaction": {
                "type": "Reaction",
                "serializable": true
              }
            },
            "result": {
              "type": "void"
            }
          }
        },
        "result": {
          "type": "RoomReactionsSubscriptionResponse",
          "serializable": false
        }
      },
      "onDiscontinuity": {
        "args": {
          "listener": {
            "type": "callback",
            "args": {
              "reason": {
                "type": "AblyErrorInfo",
                "serializable": true,
                "optional": true
              }
            },
            "result": {
              "type": "void"
            }
          }
        },
        "result": {
          "type": "OnDiscontinuitySubscriptionResponse",
          "serializable": false
        }
      }
    }
  },
  {
    "name": "RoomReactionsSubscriptionResponse",
    "syncMethods": {
      "unsubscribe": {
        "result": {
          "type": "void"
        }
      }
    }
  },
  {
    "name": "RoomStatus",
    "fields": {
      "current": {
        "type": "string",
        "serializable": true
      },
      "error": {
        "type": "ErrorInfo",
        "serializable": true
      }
    },
    "syncMethods": {
      "offAll": {
        "result": {
          "type": "void"
        }
      }
    },
    "listeners": {
      "onChange": {
        "args": {
          "listener": {
            "type": "callback",
            "args": {
              "change": {
                "type": "RoomStatusChange",
                "serializable": true
              }
            },
            "result": {
              "type": "void"
            }
          }
        },
        "result": {
          "type": "OnRoomStatusChangeResponse",
          "serializable": false
        }
      }
    }
  },
  {
    "name": "OnRoomStatusChangeResponse",
    "syncMethods": {
      "off": {
        "result": {
          "type": "void"
        }
      }
    }
  },
  {
    "name": "Room",
    "fields": {
      "roomId": {
        "type": "string",
        "serializable": true
      },
      "messages": {
        "type": "Messages",
        "serializable": false
      },
      "presence": {
        "type": "Presence",
        "serializable": false
      },
      "reactions": {
        "type": "RoomReactions",
        "serializable": false
      },
      "typing": {
        "type": "Typing",
        "serializable": false
      },
      "occupancy": {
        "type": "Occupancy",
        "serializable": false
      },
      "status": {
        "type": "RoomStatus",
        "serializable": false
      }
    },
    "syncMethods": {
      "options": {
        "result": {
          "type": "RoomOptions",
          "serializable": true
        }
      }
    },
    "asyncMethods": {
      "attach": {
        "result": {
          "type": "void"
        }
      },
      "detach": {
        "result": {
          "type": "void"
        }
      }
    }
  },
  {
    "name": "Rooms",
    "fields": {
      "clientOptions": {
        "type": "ClientOptions",
        "serializable": true
      }
    },
    "syncMethods": {
      "get": {
        "args": {
          "roomId": {
            "type": "string",
            "serializable": true
          },
          "options": {
            "type": "RoomOptions",
            "serializable": true
          }
        },
        "result": {
          "type": "Room",
          "serializable": false
        }
      }
    },
    "asyncMethods": {
      "release": {
        "args": {
          "roomId": {
            "type": "string",
            "serializable": true
          }
        },
        "result": {
          "type": "void"
        }
      }
    }
  },
  {
    "name": "Typing",
    "fields": {
      "channel": {
        "type": "RealtimeChannel",
        "serializable": false
      }
    },
    "syncMethods": {
      "unsubscribeAll": {
        "result": {
          "type": "void"
        }
      }
    },
    "asyncMethods": {
      "get": {
        "result": {
          "type": "string",
          "serializable": true,
          "array": true
        }
      },
      "start": {
        "result": {
          "type": "void"
        }
      },
      "stop": {
        "result": {
          "type": "void"
        }
      }
    },
    "listeners": {
      "subscribe": {
        "args": {
          "listener": {
            "type": "callback",
            "args": {
              "event": {
                "type": "TypingEvent",
                "serializable": false
              }
            },
            "result": {
              "type": "void"
            }
          }
        },
        "result": {
          "type": "TypingSubscriptionResponse",
          "serializable": false
        }
      },
      "onDiscontinuity": {
        "args": {
          "listener": {
            "type": "callback",
            "args": {
              "reason": {
                "type": "AblyErrorInfo",
                "serializable": true,
                "optional": true
              }
            },
            "result": {
              "type": "void"
            }
          }
        },
        "result": {
          "type": "OnDiscontinuitySubscriptionResponse",
          "serializable": false
        }
      }
    }
  },
  {
    "name": "TypingSubscriptionResponse",
    "syncMethods": {
      "unsubscribe": {
        "result": {
          "type": "void"
        }
      }
    }
  }
]
"""
}
