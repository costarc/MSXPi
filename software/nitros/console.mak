# Extra rules used with the upstream recipes/coco/dw/makefile.
$(MODDIR)/term_scdwv: scdwvdesc.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DAddr=0
$(MODDIR)/n1_scdwv: scdwvdesc.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DAddr=1
