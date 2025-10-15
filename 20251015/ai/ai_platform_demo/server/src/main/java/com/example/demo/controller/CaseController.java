package com.example.demo.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

@RestController
@RequestMapping("/api/cases")
public class CaseController {
    private final Map<String, Map<String,Object>> store = new ConcurrentHashMap<>();

    @PostMapping
    public ResponseEntity<Map<String,Object>> createCase(@RequestBody Map<String,Object> req) {
        String id = UUID.randomUUID().toString();
        Map<String,Object> rec = new HashMap<>(req);
        rec.put("caseId", id);
        rec.put("status", "RECEIVED");
        rec.put("createdAt", new Date().toString());
        store.put(id, rec);
        return ResponseEntity.ok(rec);
    }

    @GetMapping("/{id}")
    public ResponseEntity<Object> getCase(@PathVariable String id) {
        if(!store.containsKey(id)) return ResponseEntity.notFound().build();
        return ResponseEntity.ok(store.get(id));
    }

    @GetMapping
    public ResponseEntity<List<Map<String,Object>>> listCases() {
        return ResponseEntity.ok(new ArrayList<>(store.values()));
    }
}
