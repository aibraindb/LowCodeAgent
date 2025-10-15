package com.ai.server.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api")
public class ApiController {

  @GetMapping("/health")
  public Map<String,String> health(){ return Map.of("status","UP","version","0.0.1"); }

  // Minimal "configurable prompt assembly" stub
  @PostMapping("/assemble")
  public ResponseEntity<Map<String,Object>> assemble(@RequestBody Map<String,Object> cfg){
    Map<String,Object> res = new HashMap<>();
    res.put("promptId", UUID.randomUUID().toString());
    res.put("model", cfg.getOrDefault("model","mistral:tiny"));
    res.put("fiboTags", cfg.getOrDefault("fiboTags", List.of("Loan","Rate","Borrower")));
    res.put("template", "You are a document QA engine. Use provided context and answer strictly in JSON.");
    res.put("assembledAt", new Date().toString());
    return ResponseEntity.ok(res);
  }
}
